import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/cashier_cart_controller.dart';
import '../controllers/cashier_checkout_controller.dart';
import '../controllers/cashier_lookup_controller.dart';
import '../controllers/cashier_offline_sync_controller.dart';
import '../controllers/cashier_payment_calculator.dart';
import '../models/cashier_models.dart';
import '../models/user_profile.dart';
import '../services/api_client.dart';
import '../services/app_update_service.dart';
import '../services/cart_draft_store.dart';
import '../services/favorite_product_store.dart';
import '../services/offline_catalog_store.dart';
import '../services/offline_sale_queue.dart';
import '../services/pin_lock_service.dart';
import '../services/thermal_receipt_printer.dart';
import '../utils/formatters.dart';
import '../widgets/cashier/cash_movement_page.dart';
import '../widgets/cashier/cashier_pages.dart';
import '../widgets/cashier/offline_center_page.dart';
import '../widgets/cashier/payment_method_picker_sheet.dart';
import '../widgets/cashier/payment_sheet.dart';
import '../widgets/cashier/pin_lock_sheet.dart';
import '../widgets/cashier/printer_picker_sheet.dart';
import '../widgets/cashier/qty_edit_sheet.dart';
import '../widgets/cashier/receipt_dialog.dart';
import '../widgets/cashier/shift_sheet.dart';
import '../widgets/common/app_update_dialog.dart';
import 'available_products_screen.dart';
import 'login_screen.dart';

class CashierHomeScreen extends StatefulWidget {
  const CashierHomeScreen({
    super.key,
    required this.api,
    required this.appUpdateService,
    required this.user,
    this.onUnauthorized,
    this.needsDataRefresh = false,
    this.onDataRefreshed,
  });

  final ApiClient api;
  final AppUpdateService appUpdateService;
  final UserProfile user;

  /// Called when a 401 / [UnauthorizedException] is received from any request.
  /// The parent (main.dart) handles the redirect to the login screen.
  final VoidCallback? onUnauthorized;

  /// Set to true when the app resumes from background after a long pause.
  /// The screen will refresh data and then call [onDataRefreshed].
  final bool needsDataRefresh;
  final VoidCallback? onDataRefreshed;

  @override
  State<CashierHomeScreen> createState() => _CashierHomeScreenState();
}

class _CashierHomeScreenState extends State<CashierHomeScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  final _customerSearchController = TextEditingController();
  final _paidController = TextEditingController();
  final _redeemController = TextEditingController(text: '0');
  final _referenceController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _offlineQueue = OfflineSaleQueue();
  final _offlineCatalogStore = OfflineCatalogStore();
  final _pinLockService = PinLockService();
  final _favoriteProductStore = const FavoriteProductStore();
  final _cartDraftStore = const CartDraftStore();
  final _receiptPrinter = ThermalReceiptPrinter();
  final _cartController = CashierCartController();
  final _paymentCalculator = const CashierPaymentCalculator();
  late final CashierLookupController _lookupController;
  late final CashierCheckoutController _checkoutController;
  late final CashierOfflineSyncController _offlineSyncController;
  Timer? _searchDebounce;
  Timer? _customerDebounce;
  Timer? _offlineSyncTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  CashierBootstrap? _bootstrap;
  CashierShiftInfo? _activeShift;
  PaymentMethod? _selectedPaymentMethod;
  CashierCustomer? _selectedCustomer;
  List<CashierProduct> _favoriteProducts = <CashierProduct>[];

  bool _loading = true;
  bool _checkoutLoading = false;
  bool _syncingOffline = false;
  bool _loadingShift = false;
  bool _paymentSheetOpen = false;
  bool _pinLockEnabled = false;
  bool _appLocked = false;
  bool _wasOffline = false;
  bool _pinLockPromptScheduled = false;
  bool _manualSearchKeyboard = false;
  bool _restoringCartDraft = true;
  int _selectedTab = 1;
  int _offlinePendingCount = 0;
  String? _message;
  bool _messageIsError = false;

  List<CartItem> get _cart => _cartController.items;
  List<CashierProduct> get _products => _lookupController.products;
  List<CashierCustomer> get _customers => _lookupController.customers;
  bool get _searching => _lookupController.searchingProducts;
  bool get _searchingCustomer => _lookupController.searchingCustomers;
  double get _total => _cartController.total;
  int get _redeemPoints =>
      _paymentCalculator.redeemPointsFromText(_redeemController.text);
  int get _maxRedeemPoints => _paymentCalculator.maxRedeemPoints(
    customer: _selectedCustomer,
    total: _total,
  );

  double get _pointDiscount => _paymentCalculator.pointDiscount(
    redeemPoints: _redeemPoints,
    maxRedeemPoints: _maxRedeemPoints,
  );
  double get _payableTotal => _paymentCalculator.payableTotal(
    total: _total,
    pointDiscount: _pointDiscount,
  );
  int get _cartCount => _cartController.count;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lookupController = CashierLookupController(api: widget.api);
    _checkoutController = CashierCheckoutController(
      api: widget.api,
      offlineQueue: _offlineQueue,
    );
    _offlineSyncController = CashierOfflineSyncController(
      api: widget.api,
      offlineQueue: _offlineQueue,
    );
    _searchController.addListener(_onSearchChanged);
    _customerSearchController.addListener(_onCustomerSearchChanged);
    _cartController.addListener(_onCartChanged);
    _lookupController.addListener(_onLookupChanged);
    _restoreCartDraft();
    _refreshOfflineCount();
    _loadPinLockStatus(lockIfEnabled: true);
    _startConnectivityAutoSync();
    _startOfflineAutoSync();
    _loadBootstrap();
    unawaited(_loadFavoriteProducts());
    _refocusSearch();
  }

  @override
  void didUpdateWidget(CashierHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh data when the app resumes from background after a long pause
    if (widget.needsDataRefresh && !oldWidget.needsDataRefresh) {
      unawaited(_loadBootstrap());
      unawaited(_loadShift());
      widget.onDataRefreshed?.call();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      if (_pinLockEnabled && !_appLocked) {
        _schedulePinLock();
      }

      unawaited(_syncOfflineQueue(silent: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _customerDebounce?.cancel();
    _offlineSyncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _messageTimer?.cancel();
    _searchController.dispose();
    _customerSearchController.dispose();
    _paidController.dispose();
    _redeemController.dispose();
    _referenceController.dispose();
    _searchFocusNode.dispose();
    _lookupController
      ..removeListener(_onLookupChanged)
      ..dispose();
    _cartController
      ..removeListener(_onCartChanged)
      ..dispose();
    super.dispose();
  }

  void _onLookupChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onCartChanged() {
    if (!mounted) {
      return;
    }

    _syncPaidToPayable();
    setState(() {});
    if (!_restoringCartDraft) {
      unawaited(_cartDraftStore.save(_cartController.items));
    }
  }

  Future<void> _restoreCartDraft() async {
    final items = await _cartDraftStore.load();
    if (!mounted) {
      return;
    }

    _restoringCartDraft = false;
    if (items.isEmpty) {
      return;
    }

    _cartController.restore(items);
    _showMessage(
      '${items.length} item keranjang dipulihkan dari draft.',
      isError: false,
    );
  }

  // ─── Error handling ───────────────────────────────────────────────────────

  void _startOfflineAutoSync() {
    _offlineSyncTimer?.cancel();
    _offlineSyncTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _syncingOffline || _offlinePendingCount == 0) {
        return;
      }

      unawaited(_syncOfflineQueue(silent: true));
    });
  }

  void _startConnectivityAutoSync() {
    _connectivitySubscription?.cancel();
    final connectivity = Connectivity();
    _connectivitySubscription = connectivity.onConnectivityChanged.listen((
      results,
    ) {
      final isOffline =
          results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      final cameBackOnline = _wasOffline && !isOffline;
      _wasOffline = isOffline;

      if (cameBackOnline) {
        unawaited(_syncOfflineQueue(silent: true));
        unawaited(_loadBootstrap());
        unawaited(_loadFavoriteProducts());
      }
    });

    unawaited(
      connectivity.checkConnectivity().then((results) {
        _wasOffline =
            results.isEmpty ||
            results.every((r) => r == ConnectivityResult.none);
      }),
    );
  }

  Timer? _messageTimer;

  /// Central error handler. Intercepts [UnauthorizedException] and redirects
  /// to login. All other errors are shown as an inline message banner.
  void _handleError(Object error) {
    if (error is UnauthorizedException) {
      widget.onUnauthorized?.call();
      return;
    }
    if (!mounted) return;
    _showMessage(error.toString(), isError: true);
  }

  /// Tampilkan pesan banner. Pesan sukses (isError=false) otomatis hilang
  /// setelah 3 detik. Pesan error tetap tampil sampai digantikan.
  void _showMessage(String text, {required bool isError}) {
    _messageTimer?.cancel();
    setState(() {
      _message = text;
      _messageIsError = isError;
    });
    if (!isError) {
      _messageTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _message = null);
        }
      });
    }
  }

  void _clearMessage() {
    _messageTimer?.cancel();
    if (mounted) setState(() => _message = null);
  }

  // ─── Search ───────────────────────────────────────────────────────────────

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _searchDebounce?.cancel();
    _lookupController.setProductQuery(query);

    if (query.isEmpty) {
      _lookupController.clearProducts();
      if (_message == 'Produk tidak ditemukan.') {
        _clearMessage();
      }
      return;
    }

    if (_message == 'Produk tidak ditemukan.') {
      _clearMessage();
    }

    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _searchProductsRealtime(query);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _lookupController.clearProducts();
    if (_message == 'Produk tidak ditemukan.') {
      _clearMessage();
    }
    _refocusSearch();
  }

  void _refocusSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (!_manualSearchKeyboard) {
          SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        }
      }
    });
  }

  void _toggleManualSearchKeyboard() {
    setState(() => _manualSearchKeyboard = !_manualSearchKeyboard);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (_manualSearchKeyboard) {
        _searchFocusNode.requestFocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      } else {
        _searchFocusNode.requestFocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      }
    });
  }

  void _onCustomerSearchChanged() {
    final query = _customerSearchController.text.trim();
    _customerDebounce?.cancel();
    _lookupController.setCustomerQuery(query);

    if (query.isEmpty) {
      _lookupController.clearCustomers();
      return;
    }

    _customerDebounce = Timer(const Duration(milliseconds: 350), () {
      _searchCustomers(query);
    });
  }

  void _clearCustomerSearch() {
    _customerDebounce?.cancel();
    _customerSearchController.clear();
    _lookupController.clearCustomers();
  }

  void _selectCustomer(CashierCustomer customer) {
    FocusManager.instance.primaryFocus?.unfocus();
    _customerDebounce?.cancel();
    _customerSearchController.clear();
    _lookupController.clearCustomers();
    setState(() {
      _selectedCustomer = customer;
      _redeemController.text = '0';
    });
  }

  void _clearCustomer() {
    _customerDebounce?.cancel();
    _customerSearchController.clear();
    _lookupController.clearCustomers();
    setState(() {
      _selectedCustomer = null;
      _redeemController.text = '0';
    });
  }

  Future<void> _searchCustomers(String query) async {
    try {
      final result = await _lookupController.searchCustomers(query);
      if (!mounted || !result.isCurrent) {
        return;
      }
    } catch (error) {
      if (!mounted) return;
      _handleError(error);
    }
  }

  void _normalizeRedeemPoints() {
    final points = _paymentCalculator.normalizedRedeemPoints(
      text: _redeemController.text,
      customer: _selectedCustomer,
      total: _total,
    );
    final normalized = points.toString();
    if (_redeemController.text != normalized) {
      _redeemController.text = normalized;
      _redeemController.selection = TextSelection.collapsed(
        offset: normalized.length,
      );
    }
  }

  void _syncPaidToPayable() {
    _normalizeRedeemPoints();
    _paidController.text = _cart.isEmpty
        ? ''
        : _payableTotal.toStringAsFixed(0);
  }

  List<double> get _quickPaidAmounts =>
      _paymentCalculator.quickPaidAmounts(_payableTotal);

  Future<void> _refreshOfflineCount() async {
    final count = await _offlineSyncController.pendingCount();
    if (!mounted) {
      return;
    }

    setState(() => _offlinePendingCount = count);
  }

  Future<void> _loadPinLockStatus({bool lockIfEnabled = false}) async {
    final enabled = await _pinLockService.isEnabled();
    if (!mounted) {
      return;
    }

    setState(() => _pinLockEnabled = enabled);
    if (enabled && lockIfEnabled) {
      _schedulePinLock();
    }
  }

  void _schedulePinLock() {
    if (_pinLockPromptScheduled || _appLocked) {
      return;
    }

    _pinLockPromptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinLockPromptScheduled = false;
      if (!mounted || !_pinLockEnabled || _appLocked) {
        return;
      }

      unawaited(_lockApp());
    });
  }

  Future<void> _syncOfflineQueue({bool silent = false}) async {
    final pendingCount = await _offlineSyncController.pendingCount();
    if (pendingCount == 0 || _syncingOffline) {
      await _refreshOfflineCount();
      return;
    }

    setState(() => _syncingOffline = true);
    if (!silent) {
      _showMessage(
        'Sinkronisasi $pendingCount transaksi offline...',
        isError: false,
      );
    }

    try {
      final result = await _offlineSyncController.syncPending();

      if (!mounted) return;

      if (!silent && result.syncedCount > 0) {
        _showMessage(
          '${result.syncedCount} transaksi offline berhasil disinkronkan.',
          isError: false,
        );
      }
    } on NetworkException catch (error) {
      if (!mounted || silent) return;
      _handleError(error);
    } catch (error) {
      if (!mounted || silent) return;
      _showMessage('Sinkron offline terhenti: $error', isError: true);
    } finally {
      await _refreshOfflineCount();
      if (mounted) setState(() => _syncingOffline = false);
    }
  }

  Future<void> _loadBootstrap() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final data = await widget.api.bootstrap();

      setState(() {
        _bootstrap = data;
        _selectedPaymentMethod = data.paymentMethods.isEmpty
            ? null
            : data.paymentMethods.first;
        _loading = false;
      });

      // Simpan logo path ke printer service agar bisa dipakai saat print
      if (data.receiptLogoPath != null) {
        unawaited(_receiptPrinter.saveLogoPath(data.receiptLogoPath));
      }

      unawaited(_loadShift(silent: true));
      unawaited(widget.api.refreshOfflineCatalog());
      unawaited(_loadFavoriteProducts());
      unawaited(_syncOfflineQueue(silent: true));
      if (_selectedTab == 1) {
        _refocusSearch();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _handleError(error);
    }
  }

  Future<void> _loadShift({bool silent = false}) async {
    if (!silent) {
      setState(() => _loadingShift = true);
    }

    try {
      final shift = await widget.api.shift();
      if (!mounted) {
        return;
      }

      setState(() => _activeShift = shift);
    } catch (error) {
      if (!mounted || silent) return;
      _handleError(error);
    } finally {
      if (mounted && !silent) {
        setState(() => _loadingShift = false);
      }
    }
  }

  Future<void> _loadFavoriteProducts() async {
    try {
      final ids = await _favoriteProductStore.ids();
      if (ids.isEmpty) {
        if (mounted) {
          setState(() => _favoriteProducts = <CashierProduct>[]);
        }
        return;
      }

      final products = await widget.api.availableProducts();
      final availableById = {
        for (final product in products)
          if (product.stock > 0) product.id: product,
      };
      await _favoriteProductStore.prune(availableById.keys.toSet());
      final favoriteProducts = ids
          .map((id) => availableById[id])
          .whereType<CashierProduct>()
          .take(FavoriteProductStore.maxFavorites)
          .toList();

      if (!mounted) {
        return;
      }

      setState(() => _favoriteProducts = favoriteProducts);
    } catch (_) {
      if (mounted) {
        setState(() => _favoriteProducts = <CashierProduct>[]);
      }
    }
  }

  Future<void> _searchOrScanProduct() async {
    _searchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _lookupController.clearProducts();
      _refocusSearch();
      return;
    }

    _clearMessage();

    try {
      final exactProduct = await _lookupController.productByBarcodeOrNull(
        query,
      );
      if (exactProduct != null) {
        final added = _addToCart(exactProduct);
        _lookupController.clearProducts();
        _searchController.clear();
        if (added) {
          _showMessage(
            '${exactProduct.name} ditambahkan ke keranjang.',
            isError: false,
          );
        }
        _refocusSearch();
        return;
      }

      final result = await _lookupController.searchProducts(query);
      if (!mounted || !result.isCurrent) {
        return;
      }

      if (result.items.isEmpty) {
        _showMessage('Produk tidak ditemukan.', isError: false);
      } else {
        _clearMessage();
      }
    } catch (error) {
      if (!mounted) return;
      _handleError(error);
      _refocusSearch();
    }
  }

  Future<void> _searchProductsRealtime(String query) async {
    if (_message == 'Produk tidak ditemukan.') {
      _clearMessage();
    }

    try {
      final result = await _lookupController.searchProducts(query);
      if (!mounted || !result.isCurrent) {
        return;
      }

      if (result.items.isEmpty) {
        _showMessage('Produk tidak ditemukan.', isError: false);
      } else {
        _clearMessage();
      }
    } catch (error) {
      if (!mounted) return;
      _handleError(error);
    }
  }

  Future<PaymentMethod?> _selectPaymentMethod() async {
    final methods = _bootstrap?.paymentMethods ?? [];
    if (methods.isEmpty) {
      return null;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    if (!mounted) {
      return null;
    }

    final selected = await showModalBottomSheet<PaymentMethod>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => PaymentMethodPickerSheet(
        methods: methods,
        selectedPaymentMethod: _selectedPaymentMethod,
      ),
    );

    if (selected != null && mounted) {
      setState(() => _selectedPaymentMethod = selected);
    }

    return selected ?? _selectedPaymentMethod;
  }

  bool _addToCart(CashierProduct product) {
    final result = _cartController.addProduct(product);
    if (result == AddCartResult.duplicate) {
      _showMessage(
        '${product.name} sudah ada di keranjang. Tambah qty dari tombol + di keranjang.',
        isError: true,
      );
    } else if (result == AddCartResult.outOfStock) {
      _showMessage('Stok ${product.name} kosong.', isError: true);
    } else {
      // Sukses ditambahkan — reset input pencarian agar siap scan produk berikutnya
      _searchController.clear();
      _lookupController.clearProducts();
      _showMessage('${product.name} ditambahkan ke keranjang.', isError: false);
    }

    _refocusSearch();
    return result == AddCartResult.added;
  }

  void _incrementCart(CartItem item) {
    final updated = _cartController.increment(item);
    if (!updated) {
      _showMessage(
        'Stok ${item.product.name} tidak mencukupi (maks ${item.product.stock}).',
        isError: true,
      );
    }
  }

  void _decrementCart(CartItem item) {
    _cartController.decrement(item);
  }

  void _removeCartItem(CartItem item) {
    _cartController.remove(item);
    _clearMessage();
  }

  Future<void> _editCartItemQuantity(CartItem item) async {
    FocusManager.instance.primaryFocus?.unfocus();

    // Tunggu keyboard sepenuhnya turun sebelum buka sheet
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    final result = await showModalBottomSheet<QtyResult>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => QtyEditSheet(
        productName: item.product.name,
        unit: item.product.unit,
        maxStock: item.product.stock,
        initialQty: item.quantity,
      ),
    );

    if (result == null || !mounted) {
      _refocusSearch();
      return;
    }

    if (result.delete) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hapus Item'),
          content: Text('Hapus "${item.product.name}" dari keranjang?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hapus'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) {
        _refocusSearch();
        return;
      }
      _cartController.remove(item);
      _clearMessage();
    } else {
      final qty = result.qty;
      if (qty <= 0) {
        _showMessage('Jumlah harus lebih dari 0.', isError: true);
      } else if (qty > item.product.stock) {
        _showMessage(
          'Stok ${item.product.name} tidak mencukupi (maks ${item.product.stock}).',
          isError: true,
        );
      } else {
        _cartController.updateQuantity(item, qty);
        _clearMessage();
      }
    }

    _refocusSearch();
  }

  Future<void> _clearCart() async {
    if (_cart.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kosongkan Keranjang'),
        content: Text('Hapus semua ${_cart.length} item dari keranjang?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus Semua'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    _cartController.clear();
    _paidController.clear();
    _redeemController.text = '0';
    _clearMessage();
  }

  Future<void> _openPaymentSheet() async {
    if (_cart.isEmpty) {
      _showMessage('Keranjang masih kosong.', isError: true);
      return;
    }

    _syncPaidToPayable();
    FocusManager.instance.primaryFocus?.unfocus();

    _paymentSheetOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => PaymentSheet(
        cartCount: _cartCount,
        paymentMethods: _bootstrap?.paymentMethods ?? [],
        selectedPaymentMethod: _selectedPaymentMethod,
        paidController: _paidController,
        redeemController: _redeemController,
        referenceController: _referenceController,
        hasSelectedCustomer: _selectedCustomer != null,
        maxRedeemPoints: _maxRedeemPoints,
        quickPaidAmounts: _quickPaidAmounts,
        subtotal: _total,
        pointDiscount: _pointDiscount,
        payableTotal: _payableTotal,
        checkoutLoading: _checkoutLoading,
        onSelectPaymentMethod: _selectPaymentMethod,
        onRedeemMax: () {
          _redeemController.text = _maxRedeemPoints.toString();
          _syncPaidToPayable();
        },
        onCheckout: _checkout,
        onTotalsChanged: () => setState(() {}),
      ),
    );
    _paymentSheetOpen = false;

    // Hanya refocus jika keranjang masih ada isinya (belum checkout).
    // Kalau sudah checkout sukses, dialog struk sedang terbuka —
    // jangan refocus agar keyboard tidak muncul di belakang dialog.
    if (_cart.isNotEmpty) {
      _refocusSearch();
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  Future<void> _checkout() async {
    FocusManager.instance.primaryFocus?.unfocus();
    _normalizeRedeemPoints();
    final paymentMethod = _selectedPaymentMethod;
    if (_cart.isEmpty || paymentMethod == null) {
      _showMessage('Keranjang atau metode bayar belum lengkap.', isError: true);
      return;
    }

    final paidAmount =
        double.tryParse(_paidController.text.trim()) ?? _payableTotal;
    if (paidAmount < _payableTotal) {
      _showMessage('Nominal bayar kurang dari total.', isError: true);
      return;
    }

    setState(() {
      _checkoutLoading = true;
      _message = null;
    });

    try {
      final printerSettings = await _receiptPrinter.settings();
      final outcome = await _checkoutController.submit(
        items: _cart,
        paymentMethod: paymentMethod,
        amount: paidAmount,
        referenceNumber: _referenceController.text,
        customerId: _selectedCustomer?.id,
        redeemPoints: _redeemPoints.clamp(0, _maxRedeemPoints),
        receiptColumns: printerSettings.receiptColumns,
      );

      if (!mounted) return;

      _resetCheckoutState();

      if (mounted && _paymentSheetOpen) {
        Navigator.of(context).pop();
        _paymentSheetOpen = false;
      }

      if (outcome.mode == CashierCheckoutMode.online) {
        final result = outcome.result!;
        _showMessage(
          'Transaksi ${result.invoiceNumber} berhasil.',
          isError: false,
        );
        unawaited(_autoPrintReceiptIfEnabled(result, printerSettings));
        _showReceiptDialog(result);
      } else {
        _showMessage(
          'Internet putus. Transaksi disimpan ke antrian offline.',
          isError: false,
        );
        await _refreshOfflineCount();
      }
    } catch (error) {
      if (!mounted) return;
      _handleError(error);
    } finally {
      if (mounted) {
        setState(() => _checkoutLoading = false);
      }
    }
  }

  void _resetCheckoutState() {
    setState(() {
      _selectedCustomer = null;
      _searchController.clear();
      _customerSearchController.clear();
      _paidController.clear();
      _redeemController.text = '0';
      _referenceController.clear();
      _manualSearchKeyboard = false;
    });
    _lookupController.clearAll();
    _cartController.clear();
  }

  Future<void> _logout() async {
    // Konfirmasi sebelum logout agar tidak klik tidak sengaja saat shift aktif.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar'),
        content: const Text(
          'Yakin ingin keluar? Pastikan shift sudah ditutup terlebih dahulu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await widget.api.logout();
    } catch (_) {
      // Return to login even if the network is unavailable during logout.
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          api: widget.api,
          appUpdateService: widget.appUpdateService,
        ),
      ),
    );
  }

  void _showReceiptDialog(CheckoutResult result) {
    showDialog<void>(
      context: context,
      builder: (context) => ReceiptDialog(
        result: result,
        onPrint: _printReceipt,
        onCopy: _copyReceipt,
      ),
    );
  }

  Future<void> _copyReceipt(String receiptText) async {
    await Clipboard.setData(ClipboardData(text: receiptText));
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Struk disalin.')));
  }

  Future<void> _printReceipt(String receiptText) async {
    ThermalPrinterDevice? printer = await _receiptPrinter.selectedPrinter();

    if (!mounted) {
      return;
    }

    printer ??= await _selectReceiptPrinter();
    if (printer == null) {
      return;
    }

    try {
      await _receiptPrinter.printReceipt(
        printer: printer,
        receiptText: receiptText,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Struk dikirim ke ${printer.name}.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      final retry = await _showPrintErrorDialog(error.toString());
      if (retry == true && mounted) {
        await _selectReceiptPrinter(printAfterSelect: receiptText);
      }
    }
  }

  Future<void> _autoPrintReceiptIfEnabled(
    CheckoutResult result,
    ThermalPrinterSettings settings,
  ) async {
    if (!settings.autoPrint || settings.selectedPrinter == null) {
      return;
    }

    try {
      await _receiptPrinter.printReceipt(
        printer: settings.selectedPrinter!,
        receiptText: result.receiptText,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Struk otomatis dikirim ke ${settings.selectedPrinter!.name}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      // Use root ScaffoldMessenger so the snackbar is visible even when a
      // dialog (receipt dialog) is open on top of the scaffold.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          content: Text(
            'Auto print gagal: $error\nBuka struk untuk cetak ulang.',
          ),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }
  }

  Future<bool?> _showPrintErrorDialog(String message) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gagal Cetak'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Tutup'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Pilih Printer'),
          ),
        ],
      ),
    );
  }

  Future<ThermalPrinterDevice?> _selectReceiptPrinter({
    String? printAfterSelect,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();

    final selected = await showModalBottomSheet<ThermalPrinterDevice>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => PrinterPickerSheet(printer: _receiptPrinter),
    );

    if (selected == null || printAfterSelect == null) {
      if (selected != null) {
        await _receiptPrinter.saveSelectedPrinter(selected);
      }
      return selected;
    }

    try {
      await _receiptPrinter.printReceipt(
        printer: selected,
        receiptText: printAfterSelect,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Struk dikirim ke ${selected.name}.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }

    return selected;
  }

  Future<void> _showShiftSheet() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _loadShift(silent: true);

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => ShiftSheet(
        shift: _activeShift,
        api: widget.api,
        onUnauthorized: widget.onUnauthorized,
        onChanged: (shift) {
          setState(() => _activeShift = shift);
        },
      ),
    );

    _refocusSearch();
  }

  Future<void> _openReceiptFromHistory(RecentSale sale) async {
    _showMessage('Membuka struk ${sale.invoiceNumber}...', isError: false);

    try {
      final columns = await _receiptPrinter.receiptColumns();
      final result = await widget.api.receipt(sale.id, receiptColumns: columns);
      if (!mounted) return;

      _clearMessage();
      _showReceiptDialog(result);
    } catch (error) {
      if (!mounted) return;
      _handleError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 840;

        return Scaffold(
          resizeToAvoidBottomInset: true,
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      if (useRail)
                        _ColorfulNavRail(
                          selectedIndex: _selectedTab,
                          onDestinationSelected: _selectTab,
                          offlinePendingCount: _offlinePendingCount,
                        ),
                      if (useRail) const VerticalDivider(width: 1),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _refreshCurrentTab,
                          child: _currentPage(),
                        ),
                      ),
                    ],
                  ),
                ),
          bottomNavigationBar: useRail
              ? null
              : _ColorfulBottomNav(
                  selectedIndex: _selectedTab,
                  onTap: _selectTab,
                  offlinePendingCount: _offlinePendingCount,
                ),
        );
      },
    );
  }

  /// Pull-to-refresh — aksi sesuai tab aktif.
  Future<void> _refreshCurrentTab() async {
    switch (_selectedTab) {
      case 0: // Dashboard
      case 1: // Kasir
        await _loadBootstrap();
      case 2: // Kas — widget rebuild sendiri via _CashMovementPageState._reload
        setState(() {});
      case 3: // Transaksi
        setState(() {}); // FutureBuilder rebuild otomatis
      case 4: // Shift
        await _loadShift();
      case 5: // Akun — tidak ada yang perlu di-refresh
        break;
    }
  }

  void _selectTab(int index) {
    setState(() => _selectedTab = index);
    if (index == 1) {
      if (_manualSearchKeyboard) {
        setState(() => _manualSearchKeyboard = false);
      }
      _refocusSearch();
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  Widget _currentPage() {
    return switch (_selectedTab) {
      0 => _dashboardPage(),
      1 => _cashierPage(),
      2 => _cashMovementPage(),
      3 => _transactionsPage(),
      4 => _shiftPage(),
      _ => _accountPage(),
    };
  }

  Widget _cashierPage() {
    return CashierMainPage(
      api: widget.api,
      searchController: _searchController,
      searchFocusNode: _searchFocusNode,
      customerSearchController: _customerSearchController,
      manualSearchKeyboard: _manualSearchKeyboard,
      searching: _searching,
      searchingCustomer: _searchingCustomer,
      products: _products,
      favoriteProducts: _favoriteProducts,
      customers: _customers,
      selectedCustomer: _selectedCustomer,
      cart: _cart,
      cartCount: _cartCount,
      total: _total,
      pointDiscount: _pointDiscount,
      payableTotal: _payableTotal,
      checkoutLoading: _checkoutLoading,
      message: _message,
      messageIsError: _messageIsError,
      onSearchTap: () {
        if (!_manualSearchKeyboard) {
          setState(() => _manualSearchKeyboard = true);
          SystemChannels.textInput.invokeMethod<void>('TextInput.show');
        }
      },
      onSearchSubmitted: _searchOrScanProduct,
      onClearSearch: _clearSearch,
      onToggleKeyboard: _toggleManualSearchKeyboard,
      onProductTap: _addToCart,
      onClearCustomer: _clearCustomer,
      onClearCustomerSearch: _clearCustomerSearch,
      onSelectCustomer: _selectCustomer,
      onClearCart: _clearCart,
      onOpenPayment: _openPaymentSheet,
      onEditItem: _editCartItemQuantity,
      onRemoveItem: _removeCartItem,
      onDecrementItem: _decrementCart,
      onIncrementItem: _incrementCart,
    );
  }

  Widget _cashMovementPage() {
    return CashMovementPage(
      api: widget.api,
      hasActiveShift: _activeShift != null,
    );
  }

  Widget _dashboardPage() {
    return CashierDashboardPage(
      user: widget.user,
      api: widget.api,
      bootstrap: _bootstrap,
      activeShift: _activeShift,
      cartCount: _cartCount,
      offlinePendingCount: _offlinePendingCount,
      onOpenAvailableProducts: _openAvailableProducts,
      onCashier: () => _selectTab(1),
      onTransactions: () => _selectTab(3),
      onShift: () => _selectTab(4),
      onSync: _offlinePendingCount > 0 ? _syncOfflineQueue : null,
    );
  }

  Future<void> _openAvailableProducts() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AvailableProductsScreen(
          api: widget.api,
          favoriteStore: _favoriteProductStore,
        ),
      ),
    );

    if (changed == true) {
      await _loadFavoriteProducts();
    }
  }

  Widget _transactionsPage() {
    return CashierTransactionsPage(
      api: widget.api,
      onOpenReceipt: _openReceiptFromHistory,
    );
  }

  Widget _shiftPage() {
    return CashierShiftPage(
      shift: _activeShift,
      loadingShift: _loadingShift,
      onShowShiftSheet: _showShiftSheet,
    );
  }

  Widget _accountPage() {
    return CashierAccountPage(
      user: widget.user,
      receiptPrinter: _receiptPrinter,
      offlinePendingCount: _offlinePendingCount,
      onSettingsChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
      onSelectReceiptPrinter: _selectReceiptPrinter,
      onTestReceiptPrinter: _testReceiptPrinter,
      onSyncOffline: _syncOfflineQueue,
      onOpenOfflineCenter: _openOfflineCenter,
      onRefreshData: _loadBootstrap,
      onCheckServer: _checkServerConnection,
      onCheckUpdate: _checkAppUpdateManually,
      pinLockEnabled: _pinLockEnabled,
      onConfigurePinLock: _configurePinLock,
      onLockApp: _lockApp,
      onLogout: _logout,
    );
  }

  Future<void> _openOfflineCenter() async {
    FocusManager.instance.primaryFocus?.unfocus();

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OfflineCenterPage(
          offlineQueue: _offlineQueue,
          catalogStore: _offlineCatalogStore,
          syncing: _syncingOffline,
          onSyncOffline: () => _syncOfflineQueue(silent: false),
          onRefreshCatalog: widget.api.refreshOfflineCatalog,
        ),
      ),
    );

    await _refreshOfflineCount();
  }

  Future<void> _testReceiptPrinter(
    ThermalPrinterDevice printer,
    int receiptColumns,
  ) async {
    final now = DateTime.now();
    final line = '-' * receiptColumns;
    final receiptText = [
      centerReceiptText('Yosy Group', receiptColumns),
      centerReceiptText('TEST PRINT STRUK', receiptColumns),
      line,
      'Printer : ${printer.name}',
      'Waktu   : ${receiptDateTime(now)}',
      'Kertas  : ${receiptColumns >= 42 ? '80mm' : '58mm'}',
      line,
      'Jika teks ini terbaca jelas,',
      'printer struk sudah siap dipakai.',
      line,
    ].join('\n');

    try {
      await _receiptPrinter.printReceipt(
        printer: printer,
        receiptText: receiptText,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tes cetak dikirim ke ${printer.name}.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _checkAppUpdateManually() async {
    _showMessage('Mengecek update aplikasi...', isError: false);

    try {
      final update = await widget.appUpdateService.checkForUpdate();
      if (!mounted) {
        return;
      }

      if (!update.updateAvailable) {
        _showMessage('Aplikasi sudah versi terbaru.', isError: false);
        return;
      }

      _clearMessage();
      await showDialog<void>(
        context: context,
        barrierDismissible: !update.required,
        builder: (_) => AppUpdateDialog(
          update: update,
          updateService: widget.appUpdateService,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _checkServerConnection() async {
    _showMessage('Mengecek koneksi server...', isError: false);

    try {
      await widget.api.me();
      await _loadBootstrap();
      if (!mounted) {
        return;
      }

      _showMessage('Server online dan sesi kasir aktif.', isError: false);
    } on UnauthorizedException {
      widget.onUnauthorized?.call();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Cek server gagal: $error', isError: true);
    }
  }

  Future<void> _configurePinLock() async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (_pinLockEnabled) {
      final action = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'PIN aplikasi aktif',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Ubah PIN untuk mengganti kode, atau nonaktifkan jika tidak dipakai.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop('change'),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Ubah PIN'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop('clear'),
                  icon: const Icon(Icons.lock_open_outlined),
                  label: const Text('Nonaktifkan PIN'),
                ),
              ],
            ),
          ),
        ),
      );

      if (!mounted || action == null) {
        return;
      }

      if (action == 'clear') {
        await _pinLockService.clearPin();
        await _loadPinLockStatus();
        _showMessage('PIN aplikasi dinonaktifkan.', isError: false);
        return;
      }
    }

    if (!mounted) {
      return;
    }

    final pin = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const PinLockSheet(
        title: 'Atur PIN aplikasi',
        subtitle: 'PIN dipakai untuk mengunci aplikasi tanpa logout.',
        actionLabel: 'Simpan PIN',
        confirmPin: true,
      ),
    );

    if (pin == null) {
      return;
    }

    await _pinLockService.setPin(pin);
    await _loadPinLockStatus();
    _showMessage('PIN aplikasi berhasil disimpan.', isError: false);
  }

  Future<void> _lockApp() async {
    if (!await _pinLockService.isEnabled()) {
      await _configurePinLock();
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() => _appLocked = true);
    await _showUnlockSheet();
  }

  Future<void> _showUnlockSheet() async {
    while (mounted && _appLocked) {
      final pin = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        showDragHandle: false,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => const PinLockSheet(
          title: 'Aplikasi terkunci',
          subtitle: 'Masukkan PIN kasir untuk melanjutkan.',
          actionLabel: 'Buka Kunci',
        ),
      );

      if (pin == null) {
        continue;
      }

      final valid = await _pinLockService.verify(pin);
      if (!mounted) {
        return;
      }

      if (valid) {
        setState(() => _appLocked = false);
        _showMessage('Aplikasi dibuka.', isError: false);
      } else {
        _showMessage('PIN salah.', isError: true);
      }
    }
  }
}

// ─── Custom Colorful Bottom Navigation Bar ─────────────────────────────────

class _NavDestination {
  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Color color;
}

const _navDestinations = [
  _NavDestination(
    icon: Icons.grid_view_outlined,
    selectedIcon: Icons.grid_view,
    label: 'Dashboard',
    color: Color(0xFF6366F1),
  ),
  _NavDestination(
    icon: Icons.point_of_sale_outlined,
    selectedIcon: Icons.point_of_sale,
    label: 'Kasir',
    color: Color(0xFF8B5CF6),
  ),
  _NavDestination(
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
    label: 'Kas',
    color: Color(0xFF059669),
  ),
  _NavDestination(
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    label: 'Transaksi',
    color: Color(0xFF06B6D4),
  ),
  _NavDestination(
    icon: Icons.access_time_outlined,
    selectedIcon: Icons.access_time_filled,
    label: 'Shift',
    color: Color(0xFFF59E0B),
  ),
  _NavDestination(
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    label: 'Akun',
    color: Color(0xFF10B981),
  ),
];

class _ColorfulBottomNav extends StatelessWidget {
  const _ColorfulBottomNav({
    required this.selectedIndex,
    required this.onTap,
    required this.offlinePendingCount,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;
  final int offlinePendingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                for (var i = 0; i < _navDestinations.length; i++)
                  Expanded(
                    child: _ColorfulNavButton(
                      destination: _navDestinations[i],
                      isSelected: i == selectedIndex,
                      onTap: () => onTap(i),
                      badgeCount: i == 0 ? offlinePendingCount : 0,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorfulNavButton extends StatelessWidget {
  const _ColorfulNavButton({
    required this.destination,
    required this.isSelected,
    required this.onTap,
    required this.badgeCount,
  });

  final _NavDestination destination;
  final bool isSelected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = destination.color;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon container with animated background
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              width: isSelected ? 48 : 40,
              height: 30,
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      isSelected ? destination.selectedIcon : destination.icon,
                      key: ValueKey(isSelected),
                      size: 22,
                      color: isSelected ? color : const Color(0xFF9CA3AF),
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: _MiniBadge(count: badgeCount),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            // Label
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? color : const Color(0xFF9CA3AF),
              ),
              child: Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          height: 1.3,
        ),
      ),
    );
  }
}

// ─── Custom Colorful Navigation Rail (tablet / wide layout) ────────────────

class _ColorfulNavRail extends StatelessWidget {
  const _ColorfulNavRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.offlinePendingCount,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final int offlinePendingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Brand mark at top
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.storefront_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(height: 20),
            // Navigation items
            for (var i = 0; i < _navDestinations.length; i++)
              _ColorfulRailButton(
                destination: _navDestinations[i],
                isSelected: i == selectedIndex,
                onTap: () => onDestinationSelected(i),
                badgeCount: i == 0 ? offlinePendingCount : 0,
              ),
          ],
        ),
      ),
    );
  }
}

class _ColorfulRailButton extends StatelessWidget {
  const _ColorfulRailButton({
    required this.destination,
    required this.isSelected,
    required this.onTap,
    required this.badgeCount,
  });

  final _NavDestination destination;
  final bool isSelected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = destination.color;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      isSelected ? destination.selectedIcon : destination.icon,
                      key: ValueKey(isSelected),
                      size: 23,
                      color: isSelected ? color : const Color(0xFF9CA3AF),
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -8,
                      top: -6,
                      child: _MiniBadge(count: badgeCount),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? color : const Color(0xFF9CA3AF),
                ),
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
