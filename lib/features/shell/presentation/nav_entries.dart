import 'package:flutter/material.dart';

import '../../../core/classes/enums.dart';
import '../../../core/localization/app_text.dart';
import '../../accounting/accounting_routes.dart';
import '../../ageing/ageing_page.dart';
import '../../audit/audit_page.dart';
import '../../catalog/catalog_routes.dart';
import '../../dashboard/dashboard_routes.dart';
import '../../expiry/expiry_page.dart';
import '../../guide/guide_page.dart';
import '../../insights/insights_page.dart';
import '../../inventory/inventory_routes.dart';
import '../../labels/labels_page.dart';
import '../../orders/orders_page.dart';
import '../../parties/parties_routes.dart';
import '../../pos/pos_routes.dart';
import '../../printing/printing_routes.dart';
import '../../promotions/promotions_page.dart';
import '../../purchases/purchases_routes.dart';
import '../../sales/sales_routes.dart';
import '../../settings/settings_routes.dart';
import '../../stocktake/stocktake_page.dart';
import '../../shifts/shifts_routes.dart';
import '../../users/presentation/pages/permissions_page.dart';
import '../../users/users_routes.dart';
import 'cubit/shell_cubit.dart';

List<NavEntry> buildNavEntries() => <NavEntry>[
      NavEntry(
        id: 'dashboard',
        groupKey: '',
        labelKey: AppText.navDashboard,
        icon: Icons.space_dashboard_outlined,
        activeIcon: Icons.space_dashboard,
        builder: DashboardRoutes.standalone,
        roles: const <UserRole>[
          UserRole.owner,
          UserRole.manager,
          UserRole.accountant,
        ],
      ),
      NavEntry(
        id: 'pos',
        groupKey: '',
        labelKey: AppText.navPos,
        icon: Icons.point_of_sale_outlined,
        activeIcon: Icons.point_of_sale,
        builder: PosRoutes.standalone,
        roles: const <UserRole>[
          UserRole.owner,
          UserRole.manager,
          UserRole.cashier,
        ],
      ),

      //? ── Selling ──────────────────────────────────────────────────────────
      NavEntry(
        id: 'sales',
        groupKey: AppText.navGroupSell,
        labelKey: AppText.navSales,
        icon: Icons.receipt_long_outlined,
        activeIcon: Icons.receipt_long,
        builder: SalesRoutes.standalone,
      ),
      NavEntry(
        id: 'sale_returns',
        groupKey: AppText.navGroupSell,
        labelKey: AppText.navReturns,
        icon: Icons.assignment_return_outlined,
        activeIcon: Icons.assignment_return,
        builder: SalesRoutes.returnsPage,
        roles: const <UserRole>[
          UserRole.owner,
          UserRole.manager,
          UserRole.cashier,
        ],
      ),
      NavEntry(
        id: 'customers',
        groupKey: AppText.navGroupSell,
        labelKey: AppText.navCustomers,
        icon: Icons.people_outline,
        activeIcon: Icons.people,
        builder: PartiesRoutes.customers,
      ),
      NavEntry(
        id: 'ageing',
        groupKey: AppText.navGroupSell,
        labelKey: AppText.ageingTitle,
        icon: Icons.hourglass_bottom_outlined,
        activeIcon: Icons.hourglass_bottom,
        builder: AgeingRoutes.standalone,
        roles: const <UserRole>[
          UserRole.owner,
          UserRole.manager,
          UserRole.accountant,
        ],
      ),

      // ── Buying ───────────────────────────────────────────────────────────
      NavEntry(
        id: 'purchases',
        groupKey: AppText.navGroupBuy,
        labelKey: AppText.navPurchases,
        icon: Icons.local_shipping_outlined,
        activeIcon: Icons.local_shipping,
        builder: PurchasesRoutes.standalone,
        roles: const <UserRole>[
          UserRole.owner,
          UserRole.manager,
          UserRole.accountant,
        ],
      ),
      NavEntry(
        id: 'purchase_returns',
        groupKey: AppText.navGroupBuy,
        labelKey: AppText.purchaseReturnTitle,
        icon: Icons.undo_outlined,
        activeIcon: Icons.undo,
        builder: PurchasesRoutes.returnsPage,
        roles: const <UserRole>[UserRole.owner, UserRole.manager],
      ),
      NavEntry(
        id: 'suppliers',
        groupKey: AppText.navGroupBuy,
        labelKey: AppText.navSuppliers,
        icon: Icons.storefront_outlined,
        activeIcon: Icons.storefront,
        builder: PartiesRoutes.suppliers,
        roles: const <UserRole>[
          UserRole.owner,
          UserRole.manager,
          UserRole.accountant,
        ],
      ),

      // ── Catalogue ────────────────────────────────────────────────────────
      NavEntry(
        id: 'items',
        groupKey: AppText.navGroupCatalog,
        labelKey: AppText.navItems,
        icon: Icons.inventory_2_outlined,
        activeIcon: Icons.inventory_2,
        builder: CatalogRoutes.standalone,
        roles: const <UserRole>[UserRole.owner, UserRole.manager],
      ),
      NavEntry(
        id: 'stock',
        groupKey: AppText.navGroupCatalog,
        labelKey: AppText.navStock,
        icon: Icons.warehouse_outlined,
        activeIcon: Icons.warehouse,
        builder: InventoryRoutes.standalone,
        roles: const <UserRole>[
          UserRole.owner,
          UserRole.manager,
          UserRole.accountant,
        ],
      ),

      // ── Money ────────────────────────────────────────────────────────────
      NavEntry(
        id: 'journal',
        groupKey: AppText.navGroupMoney,
        labelKey: AppText.navJournal,
        icon: Icons.menu_book_outlined,
        activeIcon: Icons.menu_book,
        builder: AccountingRoutes.journal,
        roles: const <UserRole>[
          UserRole.owner,
          UserRole.manager,
          UserRole.accountant,
        ],
      ),
      NavEntry(
        id: 'reports',
        groupKey: AppText.navGroupMoney,
        labelKey: AppText.navReports,
        icon: Icons.query_stats_outlined,
        activeIcon: Icons.query_stats,
        builder: AccountingRoutes.reports,
        roles: const <UserRole>[
          UserRole.owner,
          UserRole.manager,
          UserRole.accountant,
        ],
      ),

      // ── System ───────────────────────────────────────────────────────────
      NavEntry(
        id: 'printing',
        groupKey: AppText.navGroupSystem,
        labelKey: AppText.navPrinting,
        icon: Icons.print_outlined,
        activeIcon: Icons.print,
        builder: PrintingRoutes.standalone,
        roles: const <UserRole>[
          UserRole.owner,
          UserRole.manager,
          UserRole.cashier,
        ],
      ),
      NavEntry(
        id: 'shifts',
        groupKey: AppText.navGroupMoney,
        labelKey: AppText.navShifts,
        icon: Icons.point_of_sale_outlined,
        activeIcon: Icons.point_of_sale,
        builder: ShiftsRoutes.standalone,
        // A cashier needs this one: it is their own drawer they are counting.
        roles: const <UserRole>[
          UserRole.owner,
          UserRole.manager,
          UserRole.cashier,
        ],
      ),
      NavEntry(
        id: 'labels',
        groupKey: AppText.navGroupCatalog,
        labelKey: AppText.navLabels,
        icon: Icons.qr_code_2_outlined,
        activeIcon: Icons.qr_code_2,
        builder: LabelsRoutes.standalone,
        roles: const <UserRole>[
          UserRole.owner,
          UserRole.manager,
        ],
      ),
      NavEntry(
        id: 'orders',
        groupKey: AppText.navGroupBuy,
        labelKey: AppText.navOrders,
        icon: Icons.assignment_outlined,
        activeIcon: Icons.assignment,
        builder: OrdersRoutes.standalone,
        roles: const <UserRole>[UserRole.owner, UserRole.manager],
      ),
      NavEntry(
        id: 'stocktake',
        groupKey: AppText.navGroupCatalog,
        labelKey: AppText.navStocktake,
        icon: Icons.fact_check_outlined,
        activeIcon: Icons.fact_check,
        builder: StocktakeRoutes.standalone,
        roles: const <UserRole>[UserRole.owner, UserRole.manager],
      ),
      NavEntry(
        id: 'expiry',
        groupKey: AppText.navGroupCatalog,
        labelKey: AppText.navExpiry,
        icon: Icons.event_busy_outlined,
        activeIcon: Icons.event_busy,
        builder: ExpiryRoutes.standalone,
        roles: const <UserRole>[
          UserRole.owner,
          UserRole.manager,
          UserRole.cashier,
        ],
      ),
      NavEntry(
        id: 'promotions',
        groupKey: AppText.navGroupSell,
        labelKey: AppText.navPromotions,
        icon: Icons.local_offer_outlined,
        activeIcon: Icons.local_offer,
        builder: PromotionsRoutes.standalone,
        roles: const <UserRole>[UserRole.owner, UserRole.manager],
      ),
      NavEntry(
        id: 'insights',
        groupKey: AppText.navGroupMoney,
        labelKey: AppText.navInsights,
        icon: Icons.insights_outlined,
        activeIcon: Icons.insights,
        builder: InsightsRoutes.standalone,
        roles: const <UserRole>[
          UserRole.owner,
          UserRole.manager,
          UserRole.accountant,
        ],
      ),
      NavEntry(
        id: 'permissions',
        groupKey: AppText.navGroupSystem,
        labelKey: AppText.navPermissions,
        icon: Icons.admin_panel_settings_outlined,
        activeIcon: Icons.admin_panel_settings,
        builder: PermissionsRoutes.standalone,
        roles: const <UserRole>[UserRole.owner],
      ),
      NavEntry(
        id: 'audit',
        groupKey: AppText.navGroupSystem,
        labelKey: AppText.navAudit,
        icon: Icons.history,
        activeIcon: Icons.history_toggle_off,
        builder: AuditRoutes.standalone,
        // Whoever can be held responsible for the shop's money can read it.
        roles: const <UserRole>[UserRole.owner, UserRole.manager],
      ),
      NavEntry(
        id: 'users',
        groupKey: AppText.navGroupSystem,
        labelKey: AppText.navUsers,
        icon: Icons.manage_accounts_outlined,
        activeIcon: Icons.manage_accounts,
        builder: UsersRoutes.standalone,
        roles: const <UserRole>[UserRole.owner],
      ),
      NavEntry(
        id: 'guide',
        groupKey: AppText.navGroupSystem,
        labelKey: AppText.navGuide,
        icon: Icons.help_outline,
        activeIcon: Icons.help,
        builder: GuideRoutes.standalone,
      ),
      NavEntry(
        id: 'settings',
        groupKey: AppText.navGroupSystem,
        labelKey: AppText.navSettings,
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
        builder: SettingsRoutes.standalone,
        roles: const <UserRole>[UserRole.owner, UserRole.manager],
      ),
    ];
