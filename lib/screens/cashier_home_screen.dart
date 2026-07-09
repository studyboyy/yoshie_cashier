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
import '../services/offline_return_queue.dart';
import '../services/offline_sale_history_store.dart';
import '../services/offline_sale_queue.dart';
import '../services/pin_lock_service.dart';
import '../services/thermal_receipt_printer.dart';
import '../services/training_mode_store.dart';
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
  final _paidController = TextEditingController();
  final _redeemController = TextEditingController(text: '0');
  final _referenceController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _offlineQueue = OfflineSaleQueue();
  final _offlineReturnQueue = const OfflineReturnQueue();
  final _offlineSaleHistoryStore = const OfflineSaleHistoryStore();
  final _offlineCatalogStore = OfflineCatalogStore();
  final _pinLockService = PinLockService();
  final _favoriteProductStore = const FavoriteProductStore();
  final _cartDraftStore = const CartDraftStore();
  final _receiptPrinter = ThermalReceiptPrinter();
  final _trainingModeStore = const TrainingModeStore();
  final _cartController = CashierCartController();
  final _paymentCalculator = const CashierPaymentCalculator();
  late final CashierLookupController _lookupController;
  late final CashierCheckoutController _checkoutController;
  late final CashierOfflineSyncController _offlineSyncController;
  Timer? _searchDebounce;
  Timer? _offlineSyncTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  CashierBootstrap? _bootstrap;
  CashierShiftInfo? _activeShift;
  PaymentMethod? _selectedPaymentMethod;
  List<CashierProduct> _favoriteProducts = <CashierProduct>[];
  List<RecentSale> _trainingSales = <RecentSale>[];
  List<RecentSale> _offlineSales = <RecentSale>[];

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
  bool _trainingMode = false;
  int _selectedTab = 1;
  int _offlinePendingCount = 0;
  int _trainingSaleSequence = 0;
  int _trainingSaleItemSequence = 0;
  String? _message;
  bool _messageIsError = false;

  List<CartItem> get _cart => _cartController.items;
  List<CashierProduct> get _products => _lookupController.products;
  bool get _searching => _lookupController.searchingProducts;
  double get _total => _cartController.total;
  double get _negotiationDiscount => _cartController.negotiationDiscount;
  int get _maxRedeemPoints => 0;

  double get _pointDiscount => 0;
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
      offlineReturnQueue: _offlineReturnQueue,
    );
    _searchController.addListener(_onSearchChanged);
    _cartController.addListener(_onCartChanged);
    _lookupController.addListener(_onLookupChanged);
    _restoreCartDraft();
    _refreshOfflineCount();
    _loadOfflineSales();
    _loadPinLockStatus(lockIfEnabled: true);
    _loadTrainingMode();
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
    _offlineSyncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _messageTimer?.cancel();
    _searchController.dispose();
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
      if (!mounted || _selectedTab != 1) {
        return;
      }

      _searchFocusNode.requestFocus();

      if (!_manualSearchKeyboard) {
        SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
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

  void _normalizeRedeemPoints() {
    if (_redeemController.text != '0') {
      _redeemController.text = '0';
      _redeemController.selection = const TextSelection.collapsed(offset: 1);
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

  Future<void> _loadOfflineSales() async {
    final sales = await _offlineSaleHistoryStore.all();
    if (!mounted) {
      return;
    }

    setState(() => _offlineSales = sales);
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

  Future<void> _loadTrainingMode() async {
    final enabled = await _trainingModeStore.isEnabled();
    if (!mounted) {
      return;
    }

    setState(() => _trainingMode = enabled);
  }

  Future<void> _setTrainingMode(bool enabled) async {
    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Aktifkan Mode Training?'),
          content: const Text(
            'Transaksi training tidak akan masuk laporan, tidak mengurangi stok, dan tidak disimpan ke server. Struk tetap bisa dicetak untuk latihan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Aktifkan'),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        return;
      }
    }

    await _trainingModeStore.setEnabled(enabled);
    if (!mounted) {
      return;
    }

    setState(() => _trainingMode = enabled);
    _showMessage(
      enabled
          ? 'Mode training aktif. Transaksi hanya simulasi.'
          : 'Mode training dimatikan.',
      isError: false,
    );
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

      await _offlineSaleHistoryStore.removeMany(result.syncedReferences);
      await _loadOfflineSales();

      if (!silent) {
        if (result.syncedCount > 0 && result.failedCount == 0) {
          _showMessage(
            '${result.syncedCount} transaksi offline berhasil disinkronkan.',
            isError: false,
          );
        } else if (result.syncedCount > 0 && result.failedCount > 0) {
          _showMessage(
            '${result.syncedCount} transaksi berhasil, ${result.failedCount} gagal. Sisa ${result.remainingCount} pending. Cek Sync Offline untuk detail.',
            isError: true,
          );
        } else if (result.failedCount > 0) {
          final firstError = result.failedReferences.entries.first;
          _showMessage(
            'Sync gagal: ${firstError.key} - ${firstError.value}',
            isError: true,
          );
        } else {
          _showMessage(
            'Tidak ada transaksi offline yang berhasil disinkronkan.',
            isError: true,
          );
        }
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

  Future<void> _negotiateCartItem(CartItem item) async {
    if (!item.product.canNegotiate) {
      _showMessage(
        'Nego harga hanya tersedia untuk produk Fashion.',
        isError: true,
      );
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    final result = await showModalBottomSheet<_NegotiationResult>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _NegotiationSheet(item: item),
    );

    if (result == null || !mounted) {
      _refocusSearch();
      return;
    }

    if (result.clear) {
      _cartController.clearNegotiation(item);
      _showMessage('Harga nego ${item.product.name} dihapus.', isError: false);
    } else if (result.price < 0 || result.price > item.product.price) {
      _showMessage(
        'Harga nego harus antara Rp 0 sampai ${rupiah(item.product.price)}.',
        isError: true,
      );
    } else {
      _cartController.updateNegotiatedUnitPrice(item, result.price);
      _showMessage('Harga nego ${item.product.name} disimpan.', isError: false);
    }

    _syncPaidToPayable();
    _refocusSearch();
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
        hasSelectedCustomer: false,
        maxRedeemPoints: _maxRedeemPoints,
        quickPaidAmounts: _quickPaidAmounts,
        subtotal: _total,
        negotiationDiscount: _negotiationDiscount,
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
      final receiptContext = OfflineReceiptContext(
        outletName: _bootstrap?.outlet.name ?? '-',
        cashierName: widget.user.name,
        profile: _bootstrap?.receiptProfile ?? ReceiptProfile.fromJson({}),
        outletPhone: _bootstrap?.outlet.phone,
        outletAddress: _bootstrap?.outlet.address,
      );

      if (_trainingMode) {
        final result = _trainingCheckoutResult(
          paymentMethod: paymentMethod,
          paidAmount: paidAmount,
          receiptColumns: printerSettings.receiptColumns,
          context: receiptContext,
        );
        _recordTrainingSale(result, paymentMethod);

        if (!mounted) return;

        _resetCheckoutState();

        if (mounted && _paymentSheetOpen) {
          Navigator.of(context).pop();
          _paymentSheetOpen = false;
        }

        _showMessage(
          'Mode training: transaksi simulasi selesai.',
          isError: false,
        );
        unawaited(_runPostCheckoutPrinterActions(result, printerSettings));
        _showReceiptDialog(result, training: true);
        return;
      }

      final outcome = await _checkoutController.submit(
        items: _cart,
        paymentMethod: paymentMethod,
        amount: paidAmount,
        referenceNumber: _referenceController.text,
        customerId: null,
        redeemPoints: 0,
        receiptColumns: printerSettings.receiptColumns,
        offlineReceiptContext: receiptContext,
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
        unawaited(_runPostCheckoutPrinterActions(result, printerSettings));
        _showReceiptDialog(result);
      } else {
        final result = outcome.result!;
        await _recordOfflineSale(result, paymentMethod);

        _showMessage(
          'Transaksi offline ${result.invoiceNumber} tersimpan.',
          isError: false,
        );
        unawaited(_runPostCheckoutPrinterActions(result, printerSettings));
        _showReceiptDialog(result);
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

  void _recordTrainingSale(CheckoutResult result, PaymentMethod paymentMethod) {
    _trainingSaleSequence += 1;
    final saleId = _trainingSaleSequence;
    final items = _cart.map((item) {
      _trainingSaleItemSequence += 1;

      return RecentSaleItem(
        id: _trainingSaleItemSequence,
        productId: item.product.id,
        productName: item.product.name,
        productSku: item.product.sku,
        quantity: item.quantity,
        returnedQuantity: 0,
        returnableQuantity: item.quantity,
        unitPrice: item.product.price,
        discountAmount: item.discountAmount,
        subtotal: item.subtotal,
      );
    }).toList();

    final sale = RecentSale(
      id: saleId,
      invoiceNumber: result.invoiceNumber,
      paidAt: DateTime.now(),
      grandTotal: result.grandTotal,
      paidAmount: result.paidAmount,
      changeAmount: result.changeAmount,
      paymentMethod: paymentMethod.name,
      items: items,
      receiptText: result.receiptText,
    );

    setState(() {
      _trainingSales = [sale, ..._trainingSales].take(50).toList();
    });
  }

  Future<void> _recordOfflineSale(
    CheckoutResult result,
    PaymentMethod paymentMethod,
  ) async {
    final sale = _localSaleFromCart(
      result: result,
      paymentMethod: paymentMethod,
      localOnly: true,
    );

    await _offlineSaleHistoryStore.append(sale);
    final sales = await _offlineSaleHistoryStore.all();
    if (!mounted) {
      return;
    }

    setState(() => _offlineSales = sales);
  }

  RecentSale _localSaleFromCart({
    required CheckoutResult result,
    required PaymentMethod paymentMethod,
    required bool localOnly,
  }) {
    final baseId = DateTime.now().microsecondsSinceEpoch;
    final items = _cart.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;

      return RecentSaleItem(
        id: baseId + index,
        productId: item.product.id,
        productName: item.product.name,
        productSku: item.product.sku,
        quantity: item.quantity,
        returnedQuantity: 0,
        returnableQuantity: item.quantity,
        unitPrice: item.product.price,
        discountAmount: item.discountAmount,
        subtotal: item.subtotal,
      );
    }).toList();

    return RecentSale(
      id: baseId,
      invoiceNumber: result.invoiceNumber,
      paidAt: DateTime.now(),
      grandTotal: result.grandTotal,
      paidAmount: result.paidAmount,
      changeAmount: result.changeAmount,
      paymentMethod: paymentMethod.name,
      items: items,
      receiptText: result.receiptText,
      localOnly: localOnly,
    );
  }

  CheckoutResult _trainingCheckoutResult({
    required PaymentMethod paymentMethod,
    required double paidAmount,
    required int receiptColumns,
    required OfflineReceiptContext context,
  }) {
    final now = DateTime.now();
    final draft = OfflineSaleDraft(
      localReference: 'train-${now.microsecondsSinceEpoch}',
      createdAt: now,
      cartItems: _cart.map((item) => item.toOfflineJson()).toList(),
      payment: {
        'payment_method_id': paymentMethod.id,
        'amount': paidAmount,
        if (_referenceController.text.trim().isNotEmpty)
          'reference_number': _referenceController.text.trim(),
      },
    );

    final result = _checkoutController.offlineResultFromDraft(
      draft: draft,
      paymentMethod: paymentMethod,
      receiptColumns: receiptColumns,
      context: context,
    );

    return CheckoutResult(
      invoiceNumber: draft.localReference.toUpperCase(),
      receiptText: _trainingReceiptText(
        result.receiptText,
        receiptColumns,
        context,
      ),
      grandTotal: result.grandTotal,
      paidAmount: result.paidAmount,
      changeAmount: result.changeAmount,
    );
  }

  String _trainingReceiptText(
    String receiptText,
    int receiptColumns,
    OfflineReceiptContext context,
  ) {
    final width = receiptColumns >= 42 ? 42 : 32;
    final line = '-' * width;
    final rows = receiptText.split('\n');
    final addressLines = (context.outletAddress ?? '')
        .split(',')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final addressAlreadyPrinted =
        addressLines.isNotEmpty &&
        addressLines.any((line) => receiptText.contains(line));
    final trainingHeader = [
      line,
      centerReceiptText('MODE TRAINING', width),
      centerReceiptText('SIMULASI TRANSAKSI', width),
      line,
    ];
    final trainingFooter = [
      line,
      centerReceiptText('STRUK INI HANYA LATIHAN', width),
      centerReceiptText('Tidak masuk laporan/stok', width),
    ];
    final output = <String>[];
    var headerInserted = false;
    var footerInserted = false;

    for (final row in rows) {
      if (!headerInserted && row.trim() == 'STRUK OFFLINE') {
        output.addAll(trainingHeader);
        if (!addressAlreadyPrinted) {
          for (final address in addressLines) {
            output.add(centerReceiptText(address, width));
          }
        }
        headerInserted = true;
        continue;
      }

      if (row.trim() == 'Transaksi offline tersimpan.' ||
          row.trim() == 'Sync saat internet tersedia.') {
        if (!footerInserted) {
          output.addAll(trainingFooter);
          footerInserted = true;
        }
        continue;
      }

      output.add(row);
    }

    if (!headerInserted) {
      output.insertAll(output.isEmpty ? 0 : 1, trainingHeader);
    }
    if (!footerInserted) {
      output.addAll(trainingFooter);
    }

    return output.join('\n');
  }

  void _resetCheckoutState() {
    setState(() {
      _searchController.clear();
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

  void _showReceiptDialog(CheckoutResult result, {bool training = false}) {
    showDialog<void>(
      context: context,
      builder: (context) => ReceiptDialog(
        result: result,
        training: training,
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

  Future<void> _runPostCheckoutPrinterActions(
    CheckoutResult result,
    ThermalPrinterSettings settings,
  ) async {
    await _autoPrintReceiptIfEnabled(result, settings);
    await _autoOpenCashDrawerIfEnabled(settings);
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

  Future<void> _autoOpenCashDrawerIfEnabled(
    ThermalPrinterSettings settings,
  ) async {
    if (!settings.autoOpenDrawer || settings.selectedPrinter == null) {
      return;
    }

    try {
      await _receiptPrinter.openCashDrawer(printer: settings.selectedPrinter!);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Laci kasir dibuka melalui ${settings.selectedPrinter!.name}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          content: Text('Gagal membuka laci kasir: $error'),
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
    if ((_trainingMode || sale.localOnly) && sale.receiptText != null) {
      _showReceiptDialog(
        CheckoutResult(
          invoiceNumber: sale.invoiceNumber,
          receiptText: sale.receiptText!,
          grandTotal: sale.netTotal,
          paidAmount: sale.paidAmount,
          changeAmount: sale.changeAmount,
        ),
        training: _trainingMode,
      );
      return;
    }

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

  Future<void> _printDailySalesSummary(List<RecentSale> sales) async {
    if (sales.isEmpty) {
      _showMessage('Belum ada transaksi untuk dicetak.', isError: true);
      return;
    }

    final columns = await _receiptPrinter.receiptColumns();
    final receiptText = _dailySalesSummaryReceipt(
      sales: sales,
      receiptColumns: columns,
    );

    if (!mounted) {
      return;
    }

    _showDailySummaryPreview(sales: sales, receiptText: receiptText);
  }

  void _showDailySummaryPreview({
    required List<RecentSale> sales,
    required String receiptText,
  }) {
    final total = sales.fold<double>(0, (sum, sale) => sum + sale.netTotal);

    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width < 480
                ? MediaQuery.sizeOf(context).width - 24
                : 430,
            maxHeight: MediaQuery.sizeOf(context).height < 760
                ? MediaQuery.sizeOf(context).height - 24
                : 720,
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.summarize_outlined,
                        color: Color(0xFF4F46E5),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _trainingMode
                                ? 'Preview Rekap Training'
                                : 'Preview Rekap Harian',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${sales.length} transaksi - ${rupiah(total)}',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ReceiptPaperPreview(
                    receiptText: receiptText,
                    compact: true,
                  ),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 340;
                    final buttonWidth = isNarrow
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 10) / 2;

                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: buttonWidth,
                          child: FilledButton.icon(
                            onPressed: () => _printReceipt(receiptText),
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Cetak Rekap'),
                          ),
                        ),
                        SizedBox(
                          width: buttonWidth,
                          child: OutlinedButton.icon(
                            onPressed: () => _copyReceipt(receiptText),
                            icon: const Icon(Icons.copy_outlined),
                            label: const Text('Salin'),
                          ),
                        ),
                        SizedBox(
                          width: isNarrow ? constraints.maxWidth : buttonWidth,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                            label: const Text('Tutup'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _printDailySaleReceipts(List<RecentSale> sales) async {
    if (sales.isEmpty) {
      _showMessage('Belum ada struk transaksi untuk dicetak.', isError: true);
      return;
    }

    _showMessage('Menyiapkan ${sales.length} struk...', isError: false);

    try {
      final columns = await _receiptPrinter.receiptColumns();
      final receipts = <String>[];

      for (final sale in sales) {
        if (_trainingMode && sale.receiptText != null) {
          receipts.add(sale.receiptText!);
          continue;
        }

        final result = await widget.api.receipt(
          sale.id,
          receiptColumns: columns,
        );
        receipts.add(result.receiptText);
      }

      if (!mounted) {
        return;
      }

      _clearMessage();
      await _printReceipt(receipts.join('\n\n\n'));
    } catch (error) {
      if (!mounted) {
        return;
      }

      _handleError(error);
    }
  }

  String _dailySalesSummaryReceipt({
    required List<RecentSale> sales,
    required int receiptColumns,
  }) {
    final width = receiptColumns >= 42 ? 42 : 32;
    final line = '-' * width;
    final now = DateTime.now();
    final total = sales.fold<double>(0, (sum, sale) => sum + sale.netTotal);
    final itemCount = sales.fold<int>(
      0,
      (sum, sale) =>
          sum +
          sale.items.fold<int>(
            0,
            (qty, item) =>
                qty + (item.quantity - item.returnedQuantity).clamp(0, 999999),
          ),
    );
    final rows = <String>[
      centerReceiptText(
        _bootstrap?.receiptProfile.storeName ?? 'Yosy Group',
        width,
      ),
      centerReceiptText(
        _trainingMode ? 'REKAP TRAINING HARI INI' : 'REKAP TRANSAKSI HARI INI',
        width,
      ),
      line,
      _receiptInfoLine('Tgl', receiptDateTime(now), width),
      _receiptInfoLine('Kasir', widget.user.name, width),
      _receiptInfoLine('Cabang', _bootstrap?.outlet.name ?? '-', width),
      line,
      _receiptAmountLine(
        'Transaksi',
        sales.length.toDouble(),
        width,
        suffix: ' trx',
      ),
      _receiptAmountLine('Item', itemCount.toDouble(), width, suffix: ' pcs'),
      _receiptMoneyLine('Total', total, width),
      line,
    ];

    for (final sale in sales) {
      rows.add(
        _receiptPairLine(sale.invoiceNumber, rupiah(sale.netTotal), width),
      );
      final paidAt = sale.paidAt;
      if (paidAt != null) {
        rows.add(
          _receiptPairLine(
            receiptDateTime(paidAt),
            sale.paymentMethod ?? '-',
            width,
          ),
        );
      }
    }

    rows
      ..add(line)
      ..add(
        centerReceiptText(
          _trainingMode
              ? 'Mode training - bukan laporan asli'
              : 'Dicetak dari aplikasi kasir',
          width,
        ),
      );

    return rows.join('\n');
  }

  String _receiptInfoLine(String label, String value, int width) {
    final labelWidth = width >= 42 ? 10 : 7;
    final safeLabel = _trimReceiptText(label, labelWidth).padRight(labelWidth);
    final valueWidth = (width - labelWidth).clamp(8, width).toInt();
    final safeValue = _trimReceiptText(value, valueWidth);

    return safeLabel + safeValue.padLeft(valueWidth);
  }

  String _receiptMoneyLine(String label, double value, int width) {
    return _receiptPairLine(label, rupiah(value), width);
  }

  String _receiptAmountLine(
    String label,
    double value,
    int width, {
    String suffix = '',
  }) {
    final amount = '${value.round()}$suffix';
    return _receiptPairLine(label, amount, width);
  }

  String _receiptPairLine(String left, String right, int width) {
    final safeRight = _trimReceiptText(right, width ~/ 2);
    final safeLeft = _trimReceiptText(left, width - safeRight.length - 1);
    final spaces = width - safeLeft.length - safeRight.length;

    return spaces > 0
        ? '$safeLeft${' ' * spaces}$safeRight'
        : '$safeLeft $safeRight';
  }

  String _trimReceiptText(String value, int maxLength) {
    if (maxLength <= 0) {
      return '';
    }

    return value.length <= maxLength ? value : value.substring(0, maxLength);
  }

  Future<SaleReturnResult> _returnTrainingSale(
    RecentSale sale,
    List<SaleReturnItemRequest> items,
    String reason,
  ) async {
    final qtyByItemId = {for (final item in items) item.saleItemId: item.qty};
    var refundAmount = 0.0;

    final updatedItems = sale.items.map((item) {
      final qty = qtyByItemId[item.id] ?? 0;
      if (qty <= 0) {
        return item;
      }

      final safeQty = qty > item.returnableQuantity
          ? item.returnableQuantity
          : qty;
      refundAmount += safeQty * item.finalUnitPrice;

      return item.copyWith(
        returnedQuantity: item.returnedQuantity + safeQty,
        returnableQuantity: item.returnableQuantity - safeQty,
      );
    }).toList();

    final returnedTotal = sale.returnedTotal + refundAmount;
    final updatedSale = sale.copyWith(
      items: updatedItems,
      returnedTotal: returnedTotal,
      netTotal: (sale.grandTotal - returnedTotal)
          .clamp(0, double.infinity)
          .toDouble(),
      returnStatus: returnedTotal >= sale.grandTotal ? 'full' : 'partial',
    );
    setState(() {
      _trainingSales = _trainingSales
          .map(
            (trainingSale) =>
                trainingSale.id == sale.id ? updatedSale : trainingSale,
          )
          .toList();
    });

    return SaleReturnResult(
      returnNumber: 'TRAIN-RET-${DateTime.now().millisecondsSinceEpoch}',
      refundAmount: refundAmount,
      message: reason.trim().isEmpty ? 'Retur training tersimpan.' : reason,
      sale: updatedSale,
    );
  }

  Future<SaleReturnResult> _returnOfflineSale(
    RecentSale sale,
    List<SaleReturnItemRequest> items,
    String reason,
  ) async {
    final result = _applyLocalReturn(
      sale: sale,
      items: items,
      reason: reason,
      returnPrefix: 'OFF-RET',
    );

    final updatedSale = result.sale;
    if (updatedSale != null) {
      await _offlineReturnQueue.enqueue(
        OfflineReturnDraft(
          localReference: sale.invoiceNumber,
          reason: reason.trim().isEmpty ? 'Retur offline dari kasir' : reason,
          items: items,
          createdAt: DateTime.now(),
        ),
      );
      await _offlineSaleHistoryStore.update(updatedSale);
      await _loadOfflineSales();
    }

    return result;
  }

  SaleReturnResult _applyLocalReturn({
    required RecentSale sale,
    required List<SaleReturnItemRequest> items,
    required String reason,
    required String returnPrefix,
  }) {
    final qtyByItemId = {for (final item in items) item.saleItemId: item.qty};
    var refundAmount = 0.0;

    final updatedItems = sale.items.map((item) {
      final qty = qtyByItemId[item.id] ?? 0;
      if (qty <= 0) {
        return item;
      }

      final safeQty = qty > item.returnableQuantity
          ? item.returnableQuantity
          : qty;
      refundAmount += safeQty * item.finalUnitPrice;

      return item.copyWith(
        returnedQuantity: item.returnedQuantity + safeQty,
        returnableQuantity: item.returnableQuantity - safeQty,
      );
    }).toList();

    final returnedTotal = sale.returnedTotal + refundAmount;
    final updatedSale = sale.copyWith(
      items: updatedItems,
      returnedTotal: returnedTotal,
      netTotal: (sale.grandTotal - returnedTotal)
          .clamp(0, double.infinity)
          .toDouble(),
      returnStatus: returnedTotal >= sale.grandTotal ? 'full' : 'partial',
    );

    return SaleReturnResult(
      returnNumber: '$returnPrefix-${DateTime.now().millisecondsSinceEpoch}',
      refundAmount: refundAmount,
      message: reason.trim().isEmpty ? 'Retur lokal tersimpan.' : reason,
      sale: updatedSale,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        final useRail =
            constraints.maxWidth >= 840 ||
            (isLandscape &&
                constraints.maxWidth >= 680 &&
                constraints.maxHeight >= 360);

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
                          child: _currentPageWithStatus(),
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

  Widget _currentPageWithStatus() {
    if (!_trainingMode) {
      return _currentPage();
    }

    return Column(
      children: [
        const _TrainingModeBanner(),
        Expanded(child: _currentPage()),
      ],
    );
  }

  Widget _cashierPage() {
    return CashierMainPage(
      api: widget.api,
      searchController: _searchController,
      searchFocusNode: _searchFocusNode,
      manualSearchKeyboard: _manualSearchKeyboard,
      searching: _searching,
      products: _products,
      favoriteProducts: _favoriteProducts,
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
      onClearCart: _clearCart,
      onOpenPayment: _openPaymentSheet,
      onEditItem: _editCartItemQuantity,
      onRemoveItem: _removeCartItem,
      onDecrementItem: _decrementCart,
      onIncrementItem: _incrementCart,
      onNegotiateItem: _negotiateCartItem,
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
      onPrintDailySummary: _printDailySalesSummary,
      onPrintDailyReceipts: _printDailySaleReceipts,
      offlineSales: _offlineSales,
      onForgetSyncedOfflineSales: _forgetSyncedOfflineSales,
      onOfflineReturn: _returnOfflineSale,
      trainingMode: _trainingMode,
      trainingSales: _trainingSales,
      onTrainingReturn: _returnTrainingSale,
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
      trainingMode: _trainingMode,
      onSettingsChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
      onTrainingModeChanged: _setTrainingMode,
      onSelectReceiptPrinter: _selectReceiptPrinter,
      onTestReceiptPrinter: _testReceiptPrinter,
      onTestCashDrawer: _testCashDrawer,
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

  Future<void> _forgetSyncedOfflineSales(Iterable<String> references) async {
    final normalizedReferences = references
        .map((reference) => reference.trim().toUpperCase())
        .where((reference) => reference.isNotEmpty)
        .toSet();

    if (normalizedReferences.isEmpty) {
      return;
    }

    await _offlineSaleHistoryStore.removeMany(normalizedReferences);
    await _loadOfflineSales();
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
    bool openDrawerAfterPrint,
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

      if (openDrawerAfterPrint) {
        await _receiptPrinter.openCashDrawer(printer: printer);
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            openDrawerAfterPrint
                ? 'Tes cetak dikirim dan laci dibuka lewat ${printer.name}.'
                : 'Tes cetak dikirim ke ${printer.name}.',
          ),
        ),
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

  Future<void> _testCashDrawer(ThermalPrinterDevice printer) async {
    try {
      await _receiptPrinter.openCashDrawer(printer: printer);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Perintah buka laci dikirim ke ${printer.name}.'),
        ),
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

class _TrainingModeBanner extends StatelessWidget {
  const _TrainingModeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: const Row(
        children: [
          Icon(Icons.school_outlined, color: Color(0xFFD97706), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Mode training aktif. Transaksi hanya simulasi dan tidak mengubah stok/laporan.',
              style: TextStyle(
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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

class _NegotiationResult {
  const _NegotiationResult.price(this.price) : clear = false;
  const _NegotiationResult.clear() : price = 0, clear = true;

  final double price;
  final bool clear;
}

class _NegotiationSheet extends StatefulWidget {
  const _NegotiationSheet({required this.item});

  final CartItem item;

  @override
  State<_NegotiationSheet> createState() => _NegotiationSheetState();
}

class _NegotiationSheetState extends State<_NegotiationSheet> {
  late final TextEditingController _priceController = TextEditingController(
    text: widget.item.negotiatedUnitPrice.round().toString(),
  );

  double get _price =>
      double.tryParse(_priceController.text.replaceAll('.', '').trim()) ?? 0;

  double get _unitDiscount =>
      (widget.item.product.price - _price).clamp(0, double.infinity).toDouble();

  double get _totalDiscount => _unitDiscount * widget.item.quantity;

  double get _itemTotal => _price * widget.item.quantity;

  bool get _isValid => _price >= 0 && _price <= widget.item.product.price;

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        18 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Atur Harga Nego',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Potongan hanya berlaku untuk item ini di keranjang.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.item.product.sku} - ${widget.item.quantity} ${widget.item.product.unit}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _NegotiationMetric(
                  label: 'Harga Normal',
                  value: rupiah(widget.item.product.price),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NegotiationMetric(
                  label: 'Potongan / pcs',
                  value: rupiah(_unitDiscount),
                  accent: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceController,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Harga jadi per pcs',
              prefixText: 'Rp ',
              errorText: _isValid
                  ? null
                  : 'Tidak boleh lebih besar dari harga normal.',
            ),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                _NegotiationSummaryRow(
                  label: 'Total potongan',
                  value: '-${rupiah(_totalDiscount)}',
                ),
                const SizedBox(height: 6),
                _NegotiationSummaryRow(
                  label: 'Total item',
                  value: rupiah(_itemTotal),
                  strong: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(const _NegotiationResult.clear()),
                  child: const Text('Hapus Nego'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isValid
                      ? () => Navigator.of(
                          context,
                        ).pop(_NegotiationResult.price(_price))
                      : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Simpan'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NegotiationMetric extends StatelessWidget {
  const _NegotiationMetric({
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent ? const Color(0xFFDCFCE7) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent ? const Color(0xFFBBF7D0) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: accent ? const Color(0xFF047857) : const Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent ? const Color(0xFF047857) : const Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _NegotiationSummaryRow extends StatelessWidget {
  const _NegotiationSummaryRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: const Color(0xFF64748B),
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: strong ? const Color(0xFF4338CA) : const Color(0xFF047857),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
