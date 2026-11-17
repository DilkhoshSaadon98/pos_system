import 'package:flutter/material.dart';

import '../localization/app_text.dart';

//? A sentence in the three languages the app speaks.
class L {
  const L(this.en, this.ar, this.ku);

  final String en;
  final String ar;
  final String ku;

  String of(String language) => switch (language) {
        'ar' => ar,
        'ckb' => ku,
        _ => en,
      };
}

//? A part of a screen, with a title, a body and a list of actions the user can take.
class GuidePart {
  const GuidePart(this.title, this.body, {this.actions = const <L>[]});

  final L title;
  final L body;
  final List<L> actions;
}

//? "I want to …" → the screen that does it.
class GuideTask {
  const GuideTask(this.want, this.sectionId, {this.how});

  final L want;
  final String sectionId;
  final L? how;
}

//? One screen of the app, explained.
class GuideSection {
  const GuideSection({
    required this.id,
    required this.icon,
    required this.groupKey,
    required this.title,
    required this.purpose,
    this.canDo = const <L>[],
    this.parts = const <GuidePart>[],
    this.tips = const <L>[],
    this.tasks = const <GuideTask>[],
  });
  final String id;

  final IconData icon;
  final String groupKey;
  final L title;
  final L purpose;
  final List<L> canDo;
  final List<GuidePart> parts;
  final List<L> tips;
  final List<GuideTask> tasks;

  //? Everything written about this screen, flattened — what the search box
  //? looks through.
  String haystack(String language) => <String>[
        title.of(language),
        purpose.of(language),
        for (final L l in canDo) l.of(language),
        for (final GuidePart p in parts) ...<String>[
          p.title.of(language),
          p.body.of(language),
          for (final L l in p.actions) l.of(language),
        ],
        for (final L l in tips) l.of(language),
        for (final GuideTask t in tasks) t.want.of(language),
      ].join(' ').toLowerCase();
}

//? Every screen in the app, in sidebar order.
const List<GuideSection> guideSections = <GuideSection>[
  // ── Dashboard ────────────────────────────────────────────────────────────
  GuideSection(
    id: 'dashboard',
    icon: Icons.space_dashboard_outlined,
    groupKey: '',
    title: L('Dashboard', 'اللوحة الرئيسية', 'داشبۆرد'),
    purpose: L(
      'The state of the shop in one screen: what was sold today, what is in '
          'the drawer, what is owed, and what is about to run out.',
      'حال المحل في شاشة واحدة: ما بيع اليوم، وما في الصندوق، وما لك وما عليك، '
          'وما أوشك على النفاد.',
      'دۆخی دوکان لە یەک شاشەدا: ئەوەی ئەمڕۆ فرۆشراوە، ئەوەی لە سندوقدایە، '
          'قەرزەکان، و ئەوەی خەریکە تەواو دەبێت.',
    ),
    canDo: <L>[
      L('See today\'s invoice count, sales, profit and what went on account.',
          'ترى عدد فواتير اليوم والمبيعات والربح وما بيع بالدين.',
          'ژمارەی پسوولەی ئەمڕۆ و فرۆش و قازانج و ئەوەی بە قەرز فرۆشراوە دەبینیت.'),
      L('Read the cash in the till and the money in the bank.',
          'تقرأ النقد في الصندوق والمال في المصرف.',
          'پارەی ناو سندوق و پارەی بانک دەخوێنیتەوە.'),
      L('See the value of your stock and where it disagrees with the books.',
          'ترى قيمة المخزون وأين يختلف عن الدفاتر.',
          'نرخی کۆگاکەت دەبینیت و ئەو شوێنەی لەگەڵ دەفتەرەکان ناگونجێت.'),
      L('See the last 14 days as a chart, your best sellers, and every item '
              'that is running low or out of stock.',
          'ترى آخر ١٤ يوماً كرسم بياني، وأفضل الأصناف مبيعاً، وكل صنف أوشك أو '
              'نفد.',
          'دوایین ١٤ ڕۆژ وەک هێڵکاری دەبینیت، باشترین فرۆشراوەکان، و هەموو '
              'کاڵایەک کە کەم بووە یان تەواو بووە.'),
    ],
    tips: <L>[
      L('The "inventory difference" tile is the one to watch. It compares the '
              'stock you hold against the inventory account; anything but zero '
              'means a movement was made outside the app.',
          'مربع «فرق المخزون» هو الذي يستحق المتابعة. يقارن المخزون لديك بحساب '
              'المخزون؛ وأي رقم غير الصفر يعني حركة تمت خارج البرنامج.',
          'خشتەی «جیاوازی کۆگا» ئەوەیە کە دەبێت چاودێری بکرێت. کۆگای هەیت لەگەڵ '
              'هەژماری کۆگا بەراورد دەکات؛ هەر ژمارەیەک جگە لە سفر واتە '
              'جوڵەیەک لە دەرەوەی بەرنامەکە کراوە.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Know how the shop did today', 'أعرف كيف كان يوم المحل',
            'بزانم ئەمڕۆ دوکان چۆن بوو'),
        'dashboard',
      ),
    ],
  ),

  // ── Till ─────────────────────────────────────────────────────────────────
  GuideSection(
    id: 'pos',
    icon: Icons.point_of_sale_outlined,
    groupKey: '',
    title: L('Till', 'نقطة البيع', 'کاسە'),
    purpose: L(
      'Where you sell. Scan or tap, take the money, print the receipt.',
      'حيث تبيع. امسح أو انقر، خذ المال، اطبع الوصل.',
      'ئەو شوێنەی دەفرۆشیت. سکان بکە یان دەستی لێبدە، پارەکە وەربگرە، '
          'پسوولەکە چاپ بکە.',
    ),
    canDo: <L>[
      L('Scan a barcode, a scale label, or search by name or item code.',
          'تمسح باركود أو ملصق ميزان، أو تبحث بالاسم أو رمز الصنف.',
          'بارکۆد یان لەیبڵی تەرازوو سکان بکە، یان بە ناو و کۆدی کاڵا بگەڕێ.'),
      L('Change a quantity, a price or a unit on any line, add a note, or mark '
              'a line as a gift.',
          'تغيّر الكمية أو السعر أو الوحدة في أي سطر، وتضيف ملاحظة، أو تجعل '
              'السطر هدية.',
          'بڕ یان نرخ یان یەکە لە هەر ڕیزێکدا بگۆڕە، تێبینی زیاد بکە، یان ڕیزێک '
              'بە دیاری دابنێ.'),
      L('Give a discount on one line or on the whole bill, as a percentage or '
              'an amount.',
          'تعطي خصماً على سطر واحد أو على الفاتورة كلها، بنسبة أو بمبلغ.',
          'داشکاندن بدە بۆ یەک ڕیز یان بۆ هەموو پسوولەکە، بە ڕێژە یان بە بڕ.'),
      L('Attach a customer, spend their points, and sell on account.',
          'تربط زبوناً، وتصرف نقاطه، وتبيع بالدين.',
          'کڕیارێک ببەستە، خاڵەکانی خەرج بکە، و بە قەرز بفرۆشە.'),
      L('Take cash, card, bank or a mix, in dinars or in the second currency, '
              'and see the change before you hand it over.',
          'تستلم نقداً أو بطاقة أو حوالة أو خليطاً، بالدينار أو بالعملة '
              'الثانية، وترى الباقي قبل أن تعطيه.',
          'کاش یان کارت یان بانک یان تێکەڵ وەربگرە، بە دینار یان بە دراوی '
              'دووەم، و پاشماوەکە ببینە پێش ئەوەی بیدەیت.'),
      L('Hold a basket in a slot and come back to it, so a customer who forgot '
              'something does not block the queue.',
          'تعلّق سلة في خانة وتعود إليها، فلا يعطّل زبونٌ نسي شيئاً الطابور.',
          'سەبەتەیەک لە خانەیەکدا هەڵبگرە و بگەڕێوە بۆی، تا کڕیارێک کە شتێکی '
              'لەبیر چووە ڕیزەکە نەوەستێنێت.'),
      L('Print the last receipt again.', 'تطبع آخر وصل مرة أخرى.',
          'دوایین پسوولە دووبارە چاپ بکە.'),
    ],
    parts: <GuidePart>[
      GuidePart(
        L('The keyboard', 'لوحة المفاتيح', 'تەختەکلیل'),
        L(
          'The till is built for hands that never leave the scanner. The keys '
              'are printed along the bottom of the screen.',
          'الصندوق مصمّم ليدين لا تفارقان القارئ. المفاتيح مطبوعة أسفل الشاشة.',
          'کاسەکە بۆ دەستێک دروستکراوە کە سکانەر بەجێناهێڵێت. کلیلەکان لە '
              'خوارەوەی شاشەکە نووسراون.',
        ),
        actions: <L>[
          L('F2 search · F3 customer · F4 hold · F5 held baskets · F6 retail or '
                  'wholesale · F7 edit the selected line · F8 empty · '
                  'F9 reprint · F12 pay',
              'F2 بحث · F3 الزبون · F4 تعليق · F5 السلال المعلّقة · F6 مفرد أو '
                  'جملة · F7 تعديل السطر المحدد · F8 تفريغ · F9 إعادة طباعة · '
                  'F12 الدفع',
              'F2 گەڕان · F3 کڕیار · F4 هەڵگرتن · F5 سەبەتە هەڵگیراوەکان · '
                  'F6 تاکە یان کۆ · F7 دەستکاری ڕیزی هەڵبژێردراو · '
                  'F8 بەتاڵکردن · F9 چاپکردنەوە · F12 پارەدان'),
          L('Ctrl + up/down picks a line · Ctrl + right/left changes its '
                  'quantity · Ctrl + Delete removes it',
              'Ctrl + أعلى/أسفل يختار سطراً · Ctrl + يمين/يسار يغيّر كميته · '
                  'Ctrl + Delete يحذفه',
              'Ctrl + سەرەوە/خوارەوە ڕیزێک هەڵدەبژێرێت · Ctrl + ڕاست/چەپ بڕەکەی '
                  'دەگۆڕێت · Ctrl + Delete دەیسڕێتەوە'),
          L('Escape clears the search box — never the basket.',
              'Escape يفرغ خانة البحث — لا السلة أبداً.',
              'Escape خانەی گەڕان بەتاڵ دەکات — هەرگیز سەبەتەکە نا.'),
        ],
      ),
      GuidePart(
        L('The payment sheet', 'شاشة الدفع', 'شاشەی پارەدان'),
        L(
          'Opens with F12. Type what you were handed, or tap one of the notes '
              'the customer is likely to give you.',
          'تفتح بـ F12. اكتب ما استلمته، أو انقر إحدى الأوراق النقدية المتوقعة.',
          'بە F12 دەکرێتەوە. ئەوەی وەرتگرتووە بنووسە، یان دەست لە یەکێک لەو '
              'پارانە بدە کە کڕیار لەوانەیە بتداتێ.',
        ),
        actions: <L>[
          L('Split a bill across cash, card, bank and the second currency.',
              'تقسم الفاتورة بين النقد والبطاقة والمصرف والعملة الثانية.',
              'پسوولەکە دابەش بکە بەسەر کاش و کارت و بانک و دراوی دووەمدا.'),
          L('Leave the rest on account — the till asks for a customer first.',
              'تترك الباقي ديناً — يطلب الصندوق زبوناً أولاً.',
              'پاشماوەکە بە قەرز بهێڵەوە — کاسەکە سەرەتا داوای کڕیار دەکات.'),
          L('A sale that would take a customer past their credit limit is '
                  'refused unless you are allowed to override it.',
              'يُرفض بيع يتجاوز بالزبون سقف دينه إلا إذا كنت مخوّلاً بتجاوزه.',
              'فرۆشتنێک کە کڕیار لە سنووری قەرزی تێدەپەڕێنێت ڕەت دەکرێتەوە مەگەر '
                  'ڕێگەت پێدرابێت.'),
        ],
      ),
    ],
    tips: <L>[
      L('If the shop requires shifts, the till will not sell until a drawer is '
              'open. Open it from Cash shifts.',
          'إذا كان المحل يشترط الورديات، فلن يبيع الصندوق حتى تُفتح وردية. '
              'افتحها من «ورديات الصندوق».',
          'ئەگەر دوکان داوای شیفت بکات، کاسەکە نافرۆشێت تا سندوقێک نەکرێتەوە. '
              'لە «شیفتەکانی سندوق» بیکەرەوە.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Sell something', 'أبيع شيئاً', 'شتێک بفرۆشم'),
        'pos',
      ),
      GuideTask(
        L('Sell on account (credit)', 'أبيع بالدين', 'بە قەرز بفرۆشم'),
        'pos',
        how: L(
          'Choose a customer with F3, then in the payment sheet leave part or '
              'all of the bill unpaid.',
          'اختر زبوناً بـ F3، ثم في شاشة الدفع اترك جزءاً من الفاتورة أو كلها '
              'غير مدفوع.',
          'بە F3 کڕیارێک هەڵبژێرە، پاشان لە شاشەی پارەداندا بەشێک یان هەموو '
              'پسوولەکە بە نەدراوی بهێڵەوە.',
        ),
      ),
      GuideTask(
        L('Put a sale aside and serve the next customer',
            'أضع بيعاً جانباً وأخدم الزبون التالي',
            'فرۆشتنێک بخەمە لاوە و کڕیاری داهاتوو خزمەت بکەم'),
        'pos',
        how: L('Press F4 to hold it, F5 to bring it back.',
            'اضغط F4 لتعليقها، وF5 لاستعادتها.',
            'F4 بۆ هەڵگرتنی، F5 بۆ گەڕاندنەوەی.'),
      ),
    ],
  ),

  // ── Selling ──────────────────────────────────────────────────────────────
  GuideSection(
    id: 'sales',
    icon: Icons.receipt_long_outlined,
    groupKey: AppText.navGroupSell,
    title: L('Sales', 'المبيعات', 'فرۆشتنەکان'),
    purpose: L(
      'Every invoice the till has issued, searchable, with what it cost you '
          'and what it earned.',
      'كل فاتورة أصدرها الصندوق، قابلة للبحث، مع تكلفتها وربحها.',
      'هەموو پسوولەیەک کە کاسەکە دەریکردووە، بە گەڕان، لەگەڵ تێچوو و قازانجی.',
    ),
    canDo: <L>[
      L('Search by invoice number, customer or period.',
          'تبحث برقم الفاتورة أو الزبون أو الفترة.',
          'بە ژمارەی پسوولە یان کڕیار یان ماوە بگەڕێ.'),
      L('Open an invoice to see its lines, its discounts, its tax and how it '
              'was paid.',
          'تفتح فاتورة لترى سطورها وخصوماتها وضريبتها وكيف دُفعت.',
          'پسوولەیەک بکەرەوە بۆ بینینی ڕیزەکانی و داشکاندن و باج و چۆنیەتی '
              'پارەدانی.'),
      L('Print it again.', 'تطبعها مرة أخرى.', 'دووبارە چاپی بکە.'),
      L('Void an invoice. The stock goes back, the ledger is reversed, and the '
              'original stays on record.',
          'تلغي فاتورة. يعود المخزون، ويُعكس القيد، وتبقى الأصلية في السجل.',
          'پسوولەیەک هەڵبوەشێنەوە. کۆگا دەگەڕێتەوە، تۆمارەکە پێچەوانە دەکرێتەوە، '
              'و ئەسڵییەکە لە تۆماردا دەمێنێتەوە.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Find an old invoice', 'أجد فاتورة قديمة', 'پسوولەیەکی کۆن بدۆزمەوە'),
        'sales',
      ),
      GuideTask(
        L('Cancel a sale that should not have happened',
            'ألغي بيعاً ما كان ينبغي أن يحدث',
            'فرۆشتنێک هەڵبوەشێنمەوە کە نەدەبوو ڕووبدات'),
        'sales',
        how: L('Open the invoice and press Void.',
            'افتح الفاتورة واضغط «إلغاء».',
            'پسوولەکە بکەرەوە و «هەڵوەشاندنەوە» دابگرە.'),
      ),
    ],
  ),

  GuideSection(
    id: 'sale_returns',
    icon: Icons.assignment_return_outlined,
    groupKey: AppText.navGroupSell,
    title: L('Sales returns', 'مرتجع المبيعات', 'گەڕاندنەوەی فرۆش'),
    purpose: L(
      'A customer bringing goods back. Find the invoice, choose what is coming '
          'back, and decide how they are refunded.',
      'زبون يعيد بضاعة. جد الفاتورة، واختر ما يعود، وقرّر كيف يُرد المال.',
      'کڕیارێک کاڵا دەگەڕێنێتەوە. پسوولەکە بدۆزەرەوە، ئەوەی دەگەڕێتەوە '
          'هەڵبژێرە، و بڕیار بدە چۆن پارەکەی دەدرێتەوە.',
    ),
    canDo: <L>[
      L('Return part of an invoice or all of it — the screen knows what has '
              'already been returned.',
          'ترجع جزءاً من الفاتورة أو كلها — تعرف الشاشة ما أُرجع سابقاً.',
          'بەشێک لە پسوولەکە یان هەمووی بگەڕێنەوە — شاشەکە دەزانێت پێشتر چی '
              'گەڕێندراوەتەوە.'),
      L('Refund in cash, to a card, or against what they owe you.',
          'ترد نقداً أو إلى البطاقة أو خصماً من دينهم.',
          'بە کاش، بۆ کارت، یان لە قەرزەکەیان کەم بکەوە.'),
      L('Choose whether the goods go back on the shelf.',
          'تختار هل تعود البضاعة إلى الرف.',
          'هەڵبژێرە ئایا کاڵاکە دەگەڕێتەوە سەر ڕەف.'),
      L('Write the reason, which stays with the document.',
          'تكتب السبب، ويبقى مع المستند.',
          'هۆکارەکە بنووسە، کە لەگەڵ بەڵگەنامەکە دەمێنێتەوە.'),
    ],
    tips: <L>[
      L('A return is costed at what the goods cost when they left, not at '
              'today\'s average — so a return never invents or destroys profit.',
          'يُكلَّف المرتجع بما كلّفت البضاعة حين خرجت، لا بمتوسط اليوم — فلا '
              'يخلق المرتجع ربحاً ولا يتلفه.',
          'گەڕاندنەوە بەو تێچووە حساب دەکرێت کە کاڵاکە کاتی دەرچوونی هەیبووە، نەک '
              'بە ناوەندی ئەمڕۆ — بۆیە گەڕاندنەوە قازانج دروست ناکات و لەناوی '
              'نابات.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Take goods back from a customer', 'أستلم بضاعة من زبون',
            'کاڵا لە کڕیارێک وەربگرمەوە'),
        'sale_returns',
      ),
    ],
  ),

  GuideSection(
    id: 'customers',
    icon: Icons.people_outline,
    groupKey: AppText.navGroupSell,
    title: L('Customers', 'الزبائن', 'کڕیارەکان'),
    purpose: L(
      'Who buys from you, what they owe, and every movement on their account.',
      'من يشتري منك، وكم عليه، وكل حركة على حسابه.',
      'کێ لێت دەکڕێت، چەندی بەسەرەوەیە، و هەموو جوڵەیەک لەسەر هەژمارەکەی.',
    ),
    canDo: <L>[
      L('Add a customer with a phone, an address, a discount and a credit '
              'limit.',
          'تضيف زبوناً بهاتف وعنوان وخصم وسقف دين.',
          'کڕیارێک زیاد بکە بە تەلەفۆن و ناونیشان و داشکاندن و سنووری قەرز.'),
      L('See who owes you and filter to those with a balance only.',
          'ترى من عليه دين وتصفّي على أصحاب الأرصدة فقط.',
          'ببینە کێ قەرزاری تۆیە و تەنها ئەوانە بپاڵێوە کە باڵانسیان هەیە.'),
      L('Open a statement: every invoice, payment and return with the running '
              'balance after each.',
          'تفتح كشف حساب: كل فاتورة ودفعة ومرتجع مع الرصيد الجاري بعد كل منها.',
          'کشفی هەژمار بکەرەوە: هەموو پسوولە و پارەدان و گەڕاندنەوەیەک لەگەڵ '
              'باڵانسی جاری دوای هەریەکەیان.'),
      L('Receive money, and settle it against the oldest unpaid invoices.',
          'تستلم مالاً وتسدّده على أقدم الفواتير غير المدفوعة.',
          'پارە وەربگرە و لەسەر کۆنترین پسوولە نەدراوەکان دایبنێ.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Collect money from a customer', 'أستلم مالاً من زبون',
            'پارە لە کڕیارێک وەربگرم'),
        'customers',
        how: L('Open the customer and press Receive money.',
            'افتح الزبون واضغط «استلام مال».',
            'کڕیارەکە بکەرەوە و «وەرگرتنی پارە» دابگرە.'),
      ),
      GuideTask(
        L('Set how much credit a customer may take',
            'أحدّد كم ديناً يمكن لزبون أن يأخذ',
            'دیاری بکەم کڕیارێک چەند قەرز دەتوانێت وەربگرێت'),
        'customers',
        how: L('Edit the customer and fill in the credit limit. Zero means no '
                'limit.',
            'عدّل الزبون واملأ سقف الدين. الصفر يعني بلا سقف.',
            'کڕیارەکە دەستکاری بکە و سنووری قەرز پڕ بکەرەوە. سفر واتە بێ سنوور.'),
      ),
    ],
  ),

  GuideSection(
    id: 'ageing',
    icon: Icons.hourglass_bottom_outlined,
    groupKey: AppText.navGroupSell,
    title: L('Who owes, and for how long', 'الذمم وأعمارها',
        'قەرزەکان و تەمەنیان'),
    purpose: L(
      'Debt sorted by age rather than by size. A small very old debt is the '
          'one worth a phone call.',
      'الديون مرتّبة بالعمر لا بالحجم. الدين الصغير القديم جداً هو الذي يستحق '
          'مكالمة.',
      'قەرزەکان بەپێی تەمەن ڕیزکراون نەک قەبارە. قەرزێکی بچووکی زۆر کۆن ئەوەیە '
          'کە شایەنی تەلەفۆنێکە.',
    ),
    canDo: <L>[
      L('See every customer\'s debt split into 30, 60, 90 days and older.',
          'ترى دين كل زبون موزعاً على ٣٠ و٦٠ و٩٠ يوماً وأقدم.',
          'قەرزی هەموو کڕیارێک دابەشکراو بۆ ٣٠ و ٦٠ و ٩٠ ڕۆژ و کۆنتر دەبینیت.'),
      L('Spot at a glance who has gone past their credit limit.',
          'ترى بلمحة من تجاوز سقف دينه.',
          'بە یەک تەماشا ببینە کێ لە سنووری قەرزی تێپەڕیوە.'),
      L('Read the totals per bucket, so you know how much of what you are owed '
              'is genuinely old.',
          'تقرأ إجماليات كل فئة، فتعرف كم من ديونك قديم فعلاً.',
          'کۆی هەر بەشێک بخوێنەوە، تا بزانیت چەندی قەرزەکانت بەڕاستی کۆنن.'),
    ],
    tips: <L>[
      L('Money coming in pays the oldest bill first, so what is still owed '
              'belongs to the newest invoices. That is the rule this screen '
              'ages the balance by.',
          'المال الوارد يسدّد أقدم فاتورة أولاً، فما تبقّى من دين يعود لأحدث '
              'الفواتير. هذه هي القاعدة التي تُعمَّر بها الأرصدة هنا.',
          'پارەی هاتوو سەرەتا کۆنترین پسوولە دەداتەوە، بۆیە ئەوەی ماوە هی '
              'نوێترین پسوولەکانە. ئەمە ئەو یاسایەیە کە ئەم شاشەیە باڵانس '
              'پێی تەمەن دەکات.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Know which debts are going bad', 'أعرف أي الديون تتعثّر',
            'بزانم کام قەرزەکان خراپ دەبن'),
        'ageing',
      ),
    ],
  ),

  GuideSection(
    id: 'promotions',
    icon: Icons.local_offer_outlined,
    groupKey: AppText.navGroupSell,
    title: L('Offers', 'العروض', 'ئۆفەرەکان'),
    purpose: L(
      'Discounts the till works out by itself, and the points customers '
          'collect.',
      'خصومات يحسبها الصندوق بنفسه، والنقاط التي يجمعها الزبائن.',
      'داشکاندن کە کاسەکە خۆی دەیژمێرێت، و ئەو خاڵانەی کڕیاران کۆیان دەکەنەوە.',
    ),
    canDo: <L>[
      L('Build five kinds of offer: a percentage off, an amount off, a special '
              'price, cheaper from a quantity up, and buy some get some free.',
          'تنشئ خمسة أنواع من العروض: نسبة خصم، مبلغ خصم، سعر خاص، أرخص من كمية '
              'فأكثر، واشترِ واحصل مجاناً.',
          'پێنج جۆر ئۆفەر دروست بکە: ڕێژەی داشکاندن، بڕی داشکاندن، نرخی '
              'تایبەت، ئەرزانتر لە بڕێکەوە بەرەو سەرەوە، و بکڕە و بەخۆڕایی '
              'وەربگرە.'),
      L('Bound an offer by dates, by weekdays, by category or by a list of '
              'items, and limit it to customers with an account.',
          'تحدّ العرض بتواريخ وأيام أسبوع وقسم أو قائمة أصناف، وتقصره على أصحاب '
              'الحسابات.',
          'ئۆفەرەکە بەندبکە بە بەروار و ڕۆژانی هەفتە و بەش یان لیستی کاڵا، و '
              'تەنها بۆ خاوەن هەژمارەکان.'),
      L('See how many times each offer ran, what it brought in and what it '
              'cost you.',
          'ترى كم مرة عمل كل عرض، وكم جلب، وكم كلّف.',
          'ببینە هەر ئۆفەرێک چەند جار کاری کردووە، چەندی هێناوە و چەندی '
              'تێچووە.'),
      L('Read the points every customer holds.',
          'تقرأ نقاط كل زبون.',
          'خاڵی هەموو کڕیارێک بخوێنەوە.'),
    ],
    tips: <L>[
      L('Only one offer is applied to a line — the one that gives the customer '
              'the most. A discount you type by hand always wins and is never '
              'overwritten.',
          'يُطبَّق عرض واحد فقط على السطر — الأكثر فائدة للزبون. والخصم الذي '
              'تكتبه بيدك يفوز دائماً ولا يُستبدل.',
          'تەنها یەک ئۆفەر بۆ ڕیزێک جێبەجێ دەکرێت — ئەوەی زۆرترین سوود بە '
              'کڕیار دەدات. داشکاندنێک کە بە دەست بنووسیت هەمیشە دەبات و '
              'هەرگیز نەگۆڕدرێت.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Run a discount for a week', 'أشغّل خصماً لمدة أسبوع',
            'داشکاندنێک بۆ هەفتەیەک دابنێم'),
        'promotions',
      ),
      GuideTask(
        L('Give customers points', 'أعطي الزبائن نقاطاً',
            'خاڵ بدەم بە کڕیاران'),
        'settings',
        how: L('Switch the points scheme on in Settings, then watch the '
                'balances here.',
            'شغّل نظام النقاط في «الإعدادات»، ثم تابع الأرصدة هنا.',
            'سیستەمی خاڵ لە «ڕێکخستنەکان» هەڵبکە، پاشان باڵانسەکان لێرە '
                'ببینە.'),
      ),
    ],
  ),

  // ── Buying ───────────────────────────────────────────────────────────────
  GuideSection(
    id: 'purchases',
    icon: Icons.shopping_bag_outlined,
    groupKey: AppText.navGroupBuy,
    title: L('Purchases', 'المشتريات', 'کڕینەکان'),
    purpose: L(
      'Goods coming in. This is the only screen that changes what your stock '
          'is worth.',
      'البضاعة الواردة. هذه الشاشة الوحيدة التي تغيّر قيمة مخزونك.',
      'کاڵای هاتوو. ئەمە تەنها شاشەیەکە کە نرخی کۆگاکەت دەگۆڕێت.',
    ),
    canDo: <L>[
      L('Enter a supplier invoice line by line with quantity, unit cost, '
              'discount and tax.',
          'تدخل فاتورة مورد سطراً سطراً بالكمية والتكلفة والخصم والضريبة.',
          'پسوولەی دابینکەر ڕیز بە ڕیز بنووسە بە بڕ و تێچوو و داشکاندن و باج.'),
      L('Spread freight and fees across the lines, so the cost you record is '
              'the landed cost.',
          'توزّع الشحن والرسوم على السطور، فتكون التكلفة المسجّلة هي تكلفة '
              'الوصول.',
          'گواستنەوە و باج بەسەر ڕیزەکاندا دابەش بکە، تا ئەو تێچووەی تۆماری '
              'دەکەیت تێچووی گەیشتن بێت.'),
      L('Set a batch number and an expiry date on any line of an item that is '
              'tracked that way.',
          'تضع رقم دفعة وتاريخ صلاحية لأي سطر من صنف يُتابَع كذلك.',
          'ژمارەی لۆت و بەرواری بەسەرچوون بۆ هەر ڕیزێکی کاڵایەک کە بەو شێوەیە '
              'چاودێری دەکرێت.'),
      L('Update the selling price while you are there — the screen shows you '
              'the new margin as you type.',
          'تحدّث سعر البيع وأنت هناك — تريك الشاشة الهامش الجديد وأنت تكتب.',
          'نرخی فرۆشتن هەر لەوێ نوێ بکەرەوە — شاشەکە قازانجی نوێت پیشان دەدات '
              'کاتێک دەنووسیت.'),
      L('Pay now, in part, or leave it on the supplier\'s account.',
          'تدفع الآن أو جزئياً أو تتركها على حساب المورد.',
          'ئێستا بدە، بەشێکی، یان لەسەر هەژماری دابینکەر بیهێڵەوە.'),
    ],
    tips: <L>[
      L('Cost is a moving average. Buying the same item cheaper does not '
              'rewrite what you already hold; it moves the average by what you '
              'just bought.',
          'التكلفة متوسط متحرك. شراء الصنف نفسه بأرخص لا يعيد كتابة ما لديك؛ '
              'بل يحرّك المتوسط بمقدار ما اشتريت.',
          'تێچوو ناوەندێکی جوڵاوە. کڕینی هەمان کاڵا بە ئەرزانتر ئەوەی هەتە '
              'ناگۆڕێت؛ بەڵکو ناوەندەکە بەقەد ئەوەی کڕیوتە دەجوڵێنێت.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Enter a delivery from a supplier', 'أدخل بضاعة واردة من مورد',
            'کاڵای هاتوو لە دابینکەرێک بنووسم'),
        'purchases',
      ),
      GuideTask(
        L('Change a selling price after a price rise',
            'أغيّر سعر البيع بعد ارتفاع السعر',
            'نرخی فرۆشتن بگۆڕم دوای بەرزبوونەوەی نرخ'),
        'purchases',
        how: L('Tick "Update selling prices" on the purchase, or edit the item '
                'directly in Items.',
            'أشّر «تحديث أسعار البيع» في المشتريات، أو عدّل الصنف مباشرة من '
                '«الأصناف».',
            'لە کڕیندا «نوێکردنەوەی نرخی فرۆشتن» نیشان بکە، یان ڕاستەوخۆ لە '
                '«کاڵاکان» دەستکاری بکە.'),
      ),
    ],
  ),

  GuideSection(
    id: 'purchase_returns',
    icon: Icons.keyboard_return_outlined,
    groupKey: AppText.navGroupBuy,
    title: L('Purchase returns', 'مرتجع المشتريات', 'گەڕاندنەوەی کڕین'),
    purpose: L(
      'Sending goods back to a supplier — damaged, wrong, or unsold.',
      'إعادة بضاعة إلى مورد — تالفة أو خطأ أو لم تُبَع.',
      'گەڕاندنەوەی کاڵا بۆ دابینکەر — تێکچوو، هەڵە، یان نەفرۆشراو.',
    ),
    canDo: <L>[
      L('Find the purchase invoice and choose what goes back.',
          'تجد فاتورة الشراء وتختار ما يعود.',
          'پسوولەی کڕین بدۆزەرەوە و ئەوەی دەگەڕێتەوە هەڵبژێرە.'),
      L('Take the money back, or leave it against what you owe them.',
          'تسترد المال أو تتركه خصماً مما عليك لهم.',
          'پارەکە وەربگرەوە، یان لەسەر ئەوەی بەسەرتەوەیە بیهێڵەوە.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Send bad stock back to a supplier',
            'أعيد بضاعة تالفة إلى مورد',
            'کاڵای خراپ بۆ دابینکەر بگەڕێنمەوە'),
        'purchase_returns',
      ),
    ],
  ),

  GuideSection(
    id: 'orders',
    icon: Icons.assignment_outlined,
    groupKey: AppText.navGroupBuy,
    title: L('Purchase orders', 'أوامر الشراء', 'داواکاری کڕین'),
    purpose: L(
      'What you have asked a supplier for, and what has actually turned up.',
      'ما طلبته من مورد، وما وصل فعلاً.',
      'ئەوەی لە دابینکەر داوات کردووە، و ئەوەی بەڕاستی گەیشتووە.',
    ),
    canDo: <L>[
      L('Build an order by searching, or let the screen build one from '
              'everything below its reorder level.',
          'تبني أمراً بالبحث، أو تدع الشاشة تبنيه من كل ما هو دون حد إعادة '
              'الطلب.',
          'بە گەڕان داواکارییەک دروست بکە، یان با شاشەکە لە هەموو ئەوانەی '
              'خوار ئاستی داواکردنەوەن دروستی بکات.'),
      L('Send it, then receive what arrived — in full or in part.',
          'ترسله، ثم تستلم ما وصل — كاملاً أو جزئياً.',
          'بینێرە، پاشان ئەوەی گەیشتووە وەربگرە — تەواو یان بەشێکی.'),
      L('Receiving turns straight into a purchase invoice; whatever did not '
              'arrive stays outstanding on the order.',
          'يتحوّل الاستلام مباشرة إلى فاتورة شراء؛ وما لم يصل يبقى معلّقاً على '
              'الأمر.',
          'وەرگرتن ڕاستەوخۆ دەبێتە پسوولەی کڕین؛ ئەوەی نەگەیشتووە لەسەر '
              'داواکارییەکە دەمێنێتەوە.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Know what to order this week', 'أعرف ماذا أطلب هذا الأسبوع',
            'بزانم ئەم هەفتەیە چی داوا بکەم'),
        'orders',
        how: L('Open Purchase orders and use "Build an order from these" under '
                'the low-stock list.',
            'افتح «أوامر الشراء» واستخدم «ابنِ أمراً من هذه» أسفل قائمة النقص.',
            'داواکاری کڕین بکەرەوە و «داواکارییەک لەمانە دروست بکە» لەژێر '
                'لیستی کەمبوونەوە بەکاربهێنە.'),
      ),
    ],
  ),

  GuideSection(
    id: 'suppliers',
    icon: Icons.local_shipping_outlined,
    groupKey: AppText.navGroupBuy,
    title: L('Suppliers', 'الموردون', 'دابینکەران'),
    purpose: L(
      'Who you buy from, what you owe them, and their statement.',
      'ممن تشتري، وكم عليك لهم، وكشف حسابهم.',
      'لە کێ دەکڕیت، چەندت بەسەرەوەیە بۆیان، و کشفی هەژمارەکەیان.',
    ),
    canDo: <L>[
      L('Add a supplier and see the balance you owe.',
          'تضيف مورداً وترى الرصيد المستحق عليك.',
          'دابینکەرێک زیاد بکە و ئەو باڵانسە ببینە کە دەبێت بیدەیت.'),
      L('Pay money out and settle it against the oldest invoices.',
          'تدفع مالاً وتسدّده على أقدم الفواتير.',
          'پارە بدە و لەسەر کۆنترین پسوولەکان دایبنێ.'),
      L('Read the statement of everything you have bought and paid.',
          'تقرأ كشفاً بكل ما اشتريت ودفعت.',
          'کشفی هەموو ئەوەی کڕیوتە و داوتە بخوێنەوە.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Pay a supplier', 'أدفع لمورد', 'پارە بدەم بە دابینکەرێک'),
        'suppliers',
      ),
    ],
  ),

  // ── Catalogue ────────────────────────────────────────────────────────────
  GuideSection(
    id: 'items',
    icon: Icons.inventory_2_outlined,
    groupKey: AppText.navGroupCatalog,
    title: L('Items', 'الأصناف', 'کاڵاکان'),
    purpose: L(
      'Everything you sell, and the prices you sell it at. The heart of the '
          'catalogue.',
      'كل ما تبيعه، وبأي أسعار. قلب الكتالوك.',
      'هەموو ئەوەی دەیفرۆشیت، و بە چ نرخێک. دڵی کاتالۆگەکە.',
    ),
    canDo: <L>[
      L('Add four kinds of thing: a stocked item, a service, a group with '
              'variants, and a bundle made of other items.',
          'تضيف أربعة أنواع: صنفاً مخزنياً، وخدمة، ومجموعة بمتغيّرات، وحزمة '
              'مكوّنة من أصناف أخرى.',
          'چوار جۆر شت زیاد بکە: کاڵای کۆگایی، خزمەتگوزاری، گرووپ بە جۆراوجۆری، '
              'و پاکێجێک لە کاڵای تر پێکهاتوو.'),
      L('Give an item a photo, a category, a barcode and a code of your own.',
          'تعطي الصنف صورة وقسماً وباركود ورمزاً خاصاً بك.',
          'وێنە و بەش و بارکۆد و کۆدی خۆت بدە بە کاڵاکە.'),
      L('Sell the same item by piece, box and carton, each with its own '
              'barcode and price.',
          'تبيع الصنف نفسه بالحبة والعلبة والكرتون، ولكل منها باركود وسعر.',
          'هەمان کاڵا بە دانە و قوتوو و کارتۆن بفرۆشە، هەریەکەیان بە بارکۆد و '
              'نرخی خۆی.'),
      L('Set a retail price, a wholesale price and a floor nobody may sell '
              'below.',
          'تضع سعر مفرد وسعر جملة وحداً أدنى لا يُباع تحته.',
          'نرخی تاکە و نرخی کۆ و کەمترین نرخ دابنێ کە کەس لە خوارتری نافرۆشێت.'),
      L('Mark an item as sold by weight and give it a scale code.',
          'تجعل الصنف يُباع بالوزن وتعطيه رمز ميزان.',
          'کاڵاکە بە کێش بفرۆشرێت و کۆدی تەرازووی بدەرێ.'),
      L('Turn on batch and expiry tracking for anything that goes off.',
          'تشغّل متابعة الدفعات والصلاحية لكل ما ينتهي.',
          'چاودێری لۆت و بەسەرچوون هەڵبکە بۆ هەر شتێک کە خراپ دەبێت.'),
      L('Set a reorder level, so the item appears in the low-stock lists.',
          'تضع حد إعادة الطلب، فيظهر الصنف في قوائم النقص.',
          'ئاستی داواکردنەوە دابنێ، تا کاڵاکە لە لیستەکانی کەمبوونەوە دەربکەوێت.'),
    ],
    parts: <GuidePart>[
      GuidePart(
        L('General', 'عام', 'گشتی'),
        L('The photo, the name in three languages, the code, the category, the '
              'description, the tax rate and the expiry date.',
            'الصورة والاسم بثلاث لغات والرمز والقسم والوصف ونسبة الضريبة وتاريخ '
                'الصلاحية.',
            'وێنە و ناو بە سێ زمان و کۆد و بەش و وەسف و ڕێژەی باج و بەرواری '
                'بەسەرچوون.'),
      ),
      GuidePart(
        L('Units and prices', 'الوحدات والأسعار', 'یەکە و نرخەکان'),
        L('Every unit the item is sold in, how many base units it holds, its '
              'barcode, and its three prices. The margin is shown against the '
              'average cost as you type.',
            'كل وحدة يُباع بها الصنف، وكم وحدة أساس تحوي، وباركودها، وأسعارها '
                'الثلاثة. ويظهر الهامش مقابل متوسط التكلفة وأنت تكتب.',
            'هەموو یەکەیەک کە کاڵاکە پێی دەفرۆشرێت، چەند یەکەی بنەڕەتی لەخۆ '
                'دەگرێت، بارکۆدی، و سێ نرخەکەی. قازانج بەرامبەر ناوەندی تێچوو '
                'پیشان دەدرێت کاتێک دەنووسیت.'),
      ),
      GuidePart(
        L('Stock', 'المخزون', 'کۆگا'),
        L('What you hold, what it cost, the reorder level, and — for a brand '
              'new item only — the opening quantity and cost.',
            'ما لديك وتكلفته وحد إعادة الطلب، وللصنف الجديد فقط: الكمية '
                'والتكلفة الافتتاحية.',
            'ئەوەی هەتە و تێچووی و ئاستی داواکردنەوە، و — تەنها بۆ کاڵای نوێ — '
                'بڕ و تێچووی سەرەتایی.'),
      ),
      GuidePart(
        L('Price history', 'تاريخ الأسعار', 'مێژووی نرخ'),
        L('Every time a price moved: from what, to what, by whom and when — '
              'and what the goods have cost you on each delivery.',
            'كل مرة تحرّك فيها سعر: من كم، إلى كم، بيد من، ومتى — وكم كلّفتك '
                'البضاعة في كل توريد.',
            'هەموو جارێک کە نرخێک جوڵاوە: لە چەندەوە، بۆ چەند، بە دەستی کێ، و '
                'کەی — و کاڵاکە لە هەر گەیاندنێکدا چەندی تێچووە.'),
      ),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Add a new product', 'أضيف منتجاً جديداً', 'بەرهەمێکی نوێ زیاد بکەم'),
        'items',
      ),
      GuideTask(
        L('Put a photo on a product', 'أضع صورة على منتج',
            'وێنە بخەمە سەر بەرهەمێک'),
        'items',
        how: L('Open the item — the photo square is beside the name.',
            'افتح الصنف — مربع الصورة بجانب الاسم.',
            'کاڵاکە بکەرەوە — چوارگۆشەی وێنە لەتەنیشت ناوەکەیە.'),
      ),
      GuideTask(
        L('Find out who changed a price', 'أعرف من غيّر سعراً',
            'بزانم کێ نرخێکی گۆڕیوە'),
        'items',
        how: L('Open the item and go to the Price history tab.',
            'افتح الصنف واذهب إلى تبويب «تاريخ الأسعار».',
            'کاڵاکە بکەرەوە و بڕۆ بۆ تابی «مێژووی نرخ».'),
      ),
      GuideTask(
        L('Sell something by weight', 'أبيع شيئاً بالوزن',
            'شتێک بە کێش بفرۆشم'),
        'items',
        how: L('Edit the item, tick "Sold by weight", give it a scale code, '
                'and set the same prefix in Settings.',
            'عدّل الصنف، وأشّر «يُباع بالوزن»، وأعطه رمز ميزان، واضبط البادئة '
                'نفسها في «الإعدادات».',
            'کاڵاکە دەستکاری بکە، «بە کێش دەفرۆشرێت» نیشان بکە، کۆدی تەرازووی '
                'بدەرێ، و هەمان پێشگر لە «ڕێکخستنەکان» دابنێ.'),
      ),
    ],
  ),

  GuideSection(
    id: 'stock',
    icon: Icons.warehouse_outlined,
    groupKey: AppText.navGroupCatalog,
    title: L('Stock movements', 'حركات المخزون', 'جوڵەکانی کۆگا'),
    purpose: L(
      'Every unit that has entered or left, in order, with the balance after '
          'each one. The answer to "where did it go".',
      'كل وحدة دخلت أو خرجت، بالترتيب، مع الرصيد بعد كل حركة. جواب سؤال «أين '
          'ذهبت».',
      'هەموو یەکەیەک کە هاتووە یان چووەتە دەرەوە، بە ڕیز، لەگەڵ باڵانسی دوای '
          'هەریەکەیان. وەڵامی «بۆ کوێ چوو».',
    ),
    canDo: <L>[
      L('Filter by item, by period, and by what is out of stock or running '
              'low.',
          'تصفّي بالصنف والفترة وبما نفد أو أوشك.',
          'بە کاڵا و ماوە و ئەوەی تەواو بووە یان کەم بووە بپاڵێوە.'),
      L('See the kind of every movement — a purchase, a sale, a return, an '
              'adjustment, waste or an opening balance.',
          'ترى نوع كل حركة — شراء أو بيع أو مرتجع أو تعديل أو تلف أو رصيد '
              'افتتاحي.',
          'جۆری هەموو جوڵەیەک ببینە — کڕین، فرۆشتن، گەڕاندنەوە، ڕاستکردنەوە، '
              'زیان، یان باڵانسی سەرەتایی.'),
      L('Read the cost each movement carried and the running balance.',
          'تقرأ التكلفة التي حملتها كل حركة والرصيد الجاري.',
          'ئەو تێچووەی هەر جوڵەیەک هەڵیگرتووە و باڵانسی جاری بخوێنەوە.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Work out why a stock figure is wrong',
            'أعرف لماذا رقم المخزون خاطئ',
            'بزانم بۆچی ژمارەی کۆگا هەڵەیە'),
        'stock',
      ),
    ],
  ),

  GuideSection(
    id: 'stocktake',
    icon: Icons.fact_check_outlined,
    groupKey: AppText.navGroupCatalog,
    title: L('Stocktake', 'الجرد', 'ژمێریاری کۆگا'),
    purpose: L(
      'Counting the shelves and putting the difference into the books, once, '
          'at the end.',
      'عدّ الرفوف وإدخال الفرق إلى الدفاتر، مرة واحدة، في النهاية.',
      'ژماردنی ڕەفەکان و خستنی جیاوازییەکە ناو دەفتەرەکان، یەک جار، لە '
          'کۆتاییدا.',
    ),
    canDo: <L>[
      L('Start a count over everything, or over one category.',
          'تبدأ جرداً لكل شيء، أو لقسم واحد.',
          'ژماردنێک بۆ هەموو شتێک، یان بۆ یەک بەش دەست پێبکە.'),
      L('Fill the sheet in over a morning; the system quantity is frozen when '
              'the count starts, so nothing shifts under you.',
          'تملأ الكشف على مدى صباح؛ تُجمَّد كمية النظام عند بدء الجرد، فلا يتحرّك '
              'شيء تحتك.',
          'کاغەزەکە بە درێژایی بەیانییەک پڕ بکەرەوە؛ بڕی سیستەم لە کاتی دەستپێکی '
              'ژماردندا دەبەستێت، بۆیە هیچ لەژێر دەستت ناجوڵێت.'),
      L('See the difference at cost before you commit to it.',
          'ترى الفرق بالتكلفة قبل أن تعتمده.',
          'جیاوازییەکە بە تێچوو ببینە پێش ئەوەی پەسەندی بکەیت.'),
      L('Post it: one journal entry, and one movement for each item that '
              'actually differed.',
          'تعتمده: قيد واحد، وحركة واحدة لكل صنف اختلف فعلاً.',
          'تۆماری بکە: یەک تۆماری ڕۆژنامە، و یەک جوڵە بۆ هەر کاڵایەک کە بەڕاستی '
              'جیاواز بووە.'),
    ],
    tips: <L>[
      L('A line you did not count is left alone. The system never writes off '
              'something just because nobody reached that shelf.',
          'السطر الذي لم تعدّه يُترك كما هو. لا يشطب النظام شيئاً لمجرد أن أحداً '
              'لم يصل إلى ذلك الرف.',
          'ئەو ڕیزەی نەتژماردووە وەک خۆی دەمێنێتەوە. سیستەم هەرگیز شتێک ناسڕێتەوە '
              'تەنها لەبەر ئەوەی کەس نەگەیشتووەتە ئەو ڕەفە.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Count the shop', 'أجرد المحل', 'دوکان بژمێرم'),
        'stocktake',
      ),
    ],
  ),

  GuideSection(
    id: 'expiry',
    icon: Icons.event_busy_outlined,
    groupKey: AppText.navGroupCatalog,
    title: L('Expiry', 'الصلاحية', 'بەسەرچوون'),
    purpose: L(
      'What is about to go off, and what it is worth — the number that decides '
          'whether it is worth discounting to move it.',
      'ما أوشك على الانتهاء وقيمته — الرقم الذي يقرّر هل يستحق خصماً لتصريفه.',
      'ئەوەی خەریکە بەسەردەچێت و بەهاکەی — ئەو ژمارەیەی بڕیار دەدات ئایا '
          'شایەنی داشکاندنە بۆ فرۆشتنی.',
    ),
    canDo: <L>[
      L('Switch the window between 7, 30 and 90 days.',
          'تبدّل النافذة بين ٧ و٣٠ و٩٠ يوماً.',
          'پەنجەرەکە بگۆڕە لە نێوان ٧ و ٣٠ و ٩٠ ڕۆژدا.'),
      L('See what has already expired, and what is at risk, both at cost.',
          'ترى ما انتهى فعلاً وما هو معرّض، كلاهما بالتكلفة.',
          'ببینە چی بەسەرچووە و چی لە مەترسیدایە، هەردووکیان بە تێچوو.'),
      L('Read each batch, its number, its date and how many days it has left.',
          'تقرأ كل دفعة ورقمها وتاريخها وكم بقي لها.',
          'هەر لۆتێک و ژمارەکەی و بەرواری و ماوەی ماوەی بخوێنەوە.'),
    ],
    tips: <L>[
      L('The list is sorted by date, not by value: the question this screen '
              'answers is what you have to deal with first.',
          'القائمة مرتّبة بالتاريخ لا بالقيمة: فسؤال هذه الشاشة هو ما الذي عليك '
              'معالجته أولاً.',
          'لیستەکە بەپێی بەروار ڕیزکراوە نەک بەها: پرسیاری ئەم شاشەیە ئەوەیە '
              'کە سەرەتا دەبێت چی چارەسەر بکەیت.'),
      L('Stock leaves by earliest date first, automatically. You do not have '
              'to pick the old box.',
          'يخرج المخزون بالأقدم تاريخاً أولاً تلقائياً. لست مضطراً لاختيار '
              'العلبة القديمة.',
          'کۆگا بە کۆنترین بەروار سەرەتا دەردەچێت، بە خۆکارانە. پێویست ناکات '
              'خۆت قوتووە کۆنەکە هەڵبژێریت.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Find what is about to expire', 'أجد ما أوشك على الانتهاء',
            'ئەوە بدۆزمەوە کە خەریکە بەسەردەچێت'),
        'expiry',
      ),
    ],
  ),

  GuideSection(
    id: 'labels',
    icon: Icons.qr_code_2_outlined,
    groupKey: AppText.navGroupCatalog,
    title: L('Price labels', 'ملصقات الأسعار', 'لەیبڵی نرخ'),
    purpose: L(
      'Barcode and price labels for the shelf, printed on a sheet.',
      'ملصقات باركود وسعر للرف، تُطبع على ورقة.',
      'لەیبڵی بارکۆد و نرخ بۆ ڕەف، لەسەر پەڕەیەک چاپ دەکرێن.',
    ),
    canDo: <L>[
      L('Search and pick products, or add every result at once.',
          'تبحث وتختار منتجات، أو تضيف كل النتائج دفعة واحدة.',
          'بگەڕێ و بەرهەم هەڵبژێرە، یان هەموو ئەنجامەکان یەکجارەکی زیاد بکە.'),
      L('Set how many copies of each, the label size and how many fit a row.',
          'تحدّد عدد النسخ من كل واحد، وحجم الملصق، وكم يتّسع الصف.',
          'دیاری بکە چەند کۆپی لە هەریەکەیان، قەبارەی لەیبڵ، و چەندی لە ڕیزێکدا '
              'دەبێتەوە.'),
      L('Choose what is printed: the shop name, the product name, the price, '
              'the barcode.',
          'تختار ما يُطبع: اسم المحل، اسم المنتج، السعر، الباركود.',
          'هەڵبژێرە چی چاپ دەکرێت: ناوی دوکان، ناوی بەرهەم، نرخ، بارکۆد.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Print shelf labels after a price change',
            'أطبع ملصقات الرف بعد تغيير سعر',
            'لەیبڵی ڕەف چاپ بکەم دوای گۆڕینی نرخ'),
        'labels',
      ),
    ],
  ),

  // ── Money ────────────────────────────────────────────────────────────────
  GuideSection(
    id: 'shifts',
    icon: Icons.lock_clock_outlined,
    groupKey: AppText.navGroupMoney,
    title: L('Cash shifts', 'ورديات الصندوق', 'شیفتەکانی سندوق'),
    purpose: L(
      'Who had the drawer, what went through it, and whether it counted right '
          'at the end.',
      'من كان بيده الصندوق، وماذا مرّ عبره، وهل صحّ العدّ في النهاية.',
      'کێ سندوقی هەبووە، چی بەناویدا تێپەڕیوە، و ئایا لە کۆتاییدا ژماردنەکە '
          'ڕاست بووە.',
    ),
    canDo: <L>[
      L('Open a shift with an opening float, in dinars and in the second '
              'currency.',
          'تفتح وردية برصيد افتتاحي، بالدينار وبالعملة الثانية.',
          'شیفتێک بکەرەوە بە پارەی سەرەتایی، بە دینار و بە دراوی دووەم.'),
      L('Read an X report at any time — the drawer so far, without closing it.',
          'تقرأ تقرير X في أي وقت — حال الصندوق حتى الآن، دون إغلاقه.',
          'ڕاپۆرتی X لە هەر کاتێکدا بخوێنەوە — دۆخی سندوق تا ئێستا، بەبێ '
              'داخستنی.'),
      L('Close it with a count, and see the difference between what was '
              'expected and what was there.',
          'تغلقها بعدّ، وترى الفرق بين المتوقّع والموجود.',
          'بە ژماردنێک دایبخە، و جیاوازی نێوان چاوەڕوانکراو و بوونی ببینە.'),
      L('Print the Z report, and read every previous shift.',
          'تطبع تقرير Z، وتقرأ كل وردية سابقة.',
          'ڕاپۆرتی Z چاپ بکە، و هەموو شیفتێکی پێشوو بخوێنەوە.'),
    ],
    tips: <L>[
      L('The expected figure is the cash account\'s own balance, not a running '
              'total the till keeps — which is what makes a drawer auditable.',
          'الرقم المتوقّع هو رصيد حساب الصندوق نفسه، لا مجموعاً يحتفظ به '
              'الصندوق — وهذا ما يجعل الوردية قابلة للتدقيق.',
          'ژمارە چاوەڕوانکراوەکە باڵانسی خودی هەژماری سندوقە، نەک کۆیەک کە '
              'کاسەکە هەڵیدەگرێت — و ئەمە وایە کە شیفت شیاوی پشکنین دەکات.'),
      L('A difference is not hidden. It is posted to a "cash over and short" '
              'account, at opening as well as at closing.',
          'الفرق لا يُخفى. يُقيَّد في حساب «زيادة ونقص الصندوق»، عند الفتح كما '
              'عند الإغلاق.',
          'جیاوازی نەشاردراوەتەوە. لە هەژماری «زیادە و کەمی سندوق» تۆمار '
              'دەکرێت، لە کاتی کردنەوە وەک لە کاتی داخستن.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Start the day at the till', 'أبدأ اليوم على الصندوق',
            'ڕۆژەکە لەسەر کاسە دەست پێبکەم'),
        'shifts',
        how: L('Open a shift and type the float you are starting with.',
            'افتح وردية واكتب الرصيد الذي تبدأ به.',
            'شیفتێک بکەرەوە و ئەو پارەیە بنووسە کە پێی دەست پێدەکەیت.'),
      ),
      GuideTask(
        L('Close up and count the drawer', 'أقفل وأعدّ الصندوق',
            'دابخەم و سندوق بژمێرم'),
        'shifts',
      ),
    ],
  ),

  GuideSection(
    id: 'journal',
    icon: Icons.menu_book_outlined,
    groupKey: AppText.navGroupMoney,
    title: L('Journal', 'اليومية', 'ڕۆژنامە'),
    purpose: L(
      'Every entry the app has posted, and the chart of accounts behind them.',
      'كل قيد سجّله البرنامج، ودليل الحسابات وراءه.',
      'هەموو تۆمارێک کە بەرنامەکە کردوویەتی، و پێڕستی هەژمارەکانی پشتیان.',
    ),
    canDo: <L>[
      L('Search entries by number, source, memo or period.',
          'تبحث في القيود بالرقم أو المصدر أو البيان أو الفترة.',
          'بە ژمارە یان سەرچاوە یان تێبینی یان ماوە لە تۆمارەکاندا بگەڕێ.'),
      L('Open an entry and read both sides of it.',
          'تفتح قيداً وتقرأ طرفيه.',
          'تۆمارێک بکەرەوە و هەردوو لایەنی بخوێنەوە.'),
      L('Write a voucher by hand — receive money, pay money, or an adjustment '
              '— with as many lines as you need.',
          'تكتب سنداً بيدك — استلام أو دفع أو تسوية — بأي عدد من السطور.',
          'بە دەست وەسڵێک بنووسە — وەرگرتنی پارە، دانی پارە، یان ڕاستکردنەوە — '
              'بە هەر ژمارەیەک ڕیز.'),
      L('Reverse an entry. The original is never edited; a mirror entry is '
              'posted against it.',
          'تعكس قيداً. لا يُعدَّل الأصل أبداً؛ بل يُسجَّل قيد معاكس له.',
          'تۆمارێک پێچەوانە بکەرەوە. ئەسڵییەکە هەرگیز دەستکاری ناکرێت؛ بەڵکو '
              'تۆمارێکی پێچەوانە لە دژی تۆمار دەکرێت.'),
      L('Manage the chart of accounts.', 'تدير دليل الحسابات.',
          'پێڕستی هەژمارەکان بەڕێوە ببە.'),
    ],
    tips: <L>[
      L('An entry that does not balance is refused before it is written. That '
              'single rule is why the trial balance can be trusted.',
          'يُرفض القيد غير المتوازن قبل كتابته. هذه القاعدة وحدها هي سبب الوثوق '
              'بميزان المراجعة.',
          'ئەو تۆمارەی هاوسەنگ نییە ڕەت دەکرێتەوە پێش نووسینی. تەنها ئەم '
              'یاسایە هۆکاری متمانەکردنە بە میزانی پشکنین.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Record an expense such as rent or wages',
            'أسجّل مصروفاً كالإيجار أو الرواتب',
            'خەرجییەک تۆمار بکەم وەک کرێ یان مووچە'),
        'journal',
        how: L('Press New voucher, choose Pay money, pick the expense account '
                'and post it.',
            'اضغط «سند جديد»، اختر «دفع مال»، واختر حساب المصروف واعتمده.',
            '«وەسڵی نوێ» دابگرە، «دانی پارە» هەڵبژێرە، هەژماری خەرجی '
                'هەڵبژێرە و تۆماری بکە.'),
      ),
    ],
  ),

  GuideSection(
    id: 'reports',
    icon: Icons.assessment_outlined,
    groupKey: AppText.navGroupMoney,
    title: L('Reports', 'التقارير', 'ڕاپۆرتەکان'),
    purpose: L(
      'The three statements an accountant asks for, from the same entries the '
          'till writes.',
      'الكشوف الثلاثة التي يطلبها المحاسب، من القيود نفسها التي يكتبها الصندوق.',
      'ئەو سێ لیستەی ژمێریار داوای دەکات، لە هەمان تۆمارانەی کاسەکە دەینووسێت.',
    ),
    parts: <GuidePart>[
      GuidePart(
        L('Trial balance', 'ميزان المراجعة', 'میزانی پشکنین'),
        L('Every account with its debits and credits for the period, and the '
              'proof that the two sides agree.',
            'كل حساب بمدينه ودائنه للفترة، والدليل على تطابق الطرفين.',
            'هەموو هەژمارێک بە قەرزار و باوەڕپێکراوی ماوەکە، و بەڵگەی '
                'یەکگرتنی هەردوو لایەن.'),
      ),
      GuidePart(
        L('Income statement', 'قائمة الدخل', 'لیستی داهات'),
        L('Revenue, cost of goods sold, gross profit, expenses and what is '
              'left.',
            'الإيرادات وتكلفة البضاعة المباعة ومجمل الربح والمصروفات وما تبقّى.',
            'داهات، تێچووی کاڵای فرۆشراو، قازانجی گشتی، خەرجییەکان و ئەوەی '
                'ماوەتەوە.'),
      ),
      GuidePart(
        L('Balance sheet', 'الميزانية العمومية', 'میزانیەی گشتی'),
        L('What the shop owns, what it owes, and the owner\'s share — with the '
              'period\'s profit folded in.',
            'ما يملكه المحل وما عليه وحصة المالك — مع ربح الفترة مضموماً.',
            'ئەوەی دوکان خاوەنیەتی، ئەوەی بەسەریەوەیە، و بەشی خاوەن — لەگەڵ '
                'قازانجی ماوەکە.'),
      ),
    ],
    canDo: <L>[
      L('Choose any period.', 'تختار أي فترة.', 'هەر ماوەیەک هەڵبژێرە.'),
      L('See at once whether the books balance, and by how much if they do '
              'not.',
          'ترى فوراً هل الدفاتر متوازنة، وبكم إن لم تكن.',
          'دەستبەجێ ببینە ئایا دەفتەرەکان هاوسەنگن، و ئەگەر نا بە چەند.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Know if the shop made money this month',
            'أعرف هل ربح المحل هذا الشهر',
            'بزانم ئەم مانگە دوکان قازانجی کردووە'),
        'reports',
        how: L('Open Reports and read the income statement for the month.',
            'افتح «التقارير» واقرأ قائمة الدخل للشهر.',
            'ڕاپۆرتەکان بکەرەوە و لیستی داهاتی مانگەکە بخوێنەوە.'),
      ),
    ],
  ),

  GuideSection(
    id: 'insights',
    icon: Icons.insights_outlined,
    groupKey: AppText.navGroupMoney,
    title: L('Insights', 'التحليلات', 'تێڕوانینەکان'),
    purpose: L(
      'What is earning, what is sitting there, and when your day actually '
          'happens.',
      'ما يربح، وما يرقد، ومتى يحدث يومك فعلاً.',
      'چی قازانج دەکات، چی وەستاوە، و کەی بەڕاستی ڕۆژەکەت ڕوودەدات.',
    ),
    canDo: <L>[
      L('See stock that is not moving, ranked by what it is worth rather than '
              'by how many pieces.',
          'ترى المخزون الراكد مرتّباً بقيمته لا بعدد قطعه.',
          'ئەو کۆگایە ببینە کە ناجوڵێت، ڕیزکراو بەپێی بەهاکەی نەک ژمارەی '
              'دانەکانی.'),
      L('See what earns most — by profit, not by percentage.',
          'ترى الأكثر ربحاً — بالربح لا بالنسبة.',
          'ئەوە ببینە کە زۆرترین قازانج دەکات — بە قازانج نەک بە ڕێژە.'),
      L('See the trading day hour by hour, and your busiest hour.',
          'ترى يوم العمل ساعة بساعة، وأكثر ساعاتك ازدحاماً.',
          'ڕۆژی کارەکە کاتژمێر بە کاتژمێر ببینە، و قەرەباڵغترین کاتژمێرت.'),
      L('See what to reorder, and how many days of cover you have left.',
          'ترى ما يجب إعادة طلبه، وكم يوماً من التغطية بقي لك.',
          'ببینە چی دەبێت دووبارە داوا بکرێت، و چەند ڕۆژ پاڵپشتیت ماوە.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Find money stuck on the shelves', 'أجد مالاً عالقاً على الرفوف',
            'ئەو پارەیە بدۆزمەوە کە لەسەر ڕەفەکان گیراوە'),
        'insights',
      ),
      GuideTask(
        L('Decide when to put a second cashier on',
            'أقرّر متى أضع كاشيراً ثانياً',
            'بڕیار بدەم کەی کاسەری دووەم دابنێم'),
        'insights',
        how: L('Read the "By hour" panel.', 'اقرأ لوحة «حسب الساعة».',
            'پانێڵی «بەپێی کاتژمێر» بخوێنەوە.'),
      ),
    ],
  ),

  // ── System ───────────────────────────────────────────────────────────────
  GuideSection(
    id: 'printing',
    icon: Icons.print_outlined,
    groupKey: AppText.navGroupSystem,
    title: L('Printers', 'الطابعات', 'چاپکەرەکان'),
    purpose: L(
      'How a receipt gets out of the app and onto paper.',
      'كيف يخرج الوصل من البرنامج إلى الورق.',
      'چۆن پسوولە لە بەرنامەکەوە دەردەچێت بۆ سەر کاغەز.',
    ),
    canDo: <L>[
      L('Add a printer over the network, over USB, an installed Windows '
              'printer, the built-in Sunmi printer, or the print dialog.',
          'تضيف طابعة عبر الشبكة أو USB، أو طابعة ويندوز مثبّتة، أو طابعة '
              'Sunmi المدمجة، أو نافذة الطباعة.',
          'چاپکەرێک زیاد بکە بەسەر تۆڕ، بەسەر USB، چاپکەری ویندۆزی دانراو، '
              'چاپکەری ناوەکی Sunmi، یان پەنجەرەی چاپ.'),
      L('Choose the paper: 58 mm roll, 80 mm roll, A5 or A4.',
          'تختار الورق: رول ٥٨ ملم أو ٨٠ ملم أو A5 أو A4.',
          'کاغەزەکە هەڵبژێرە: ڕۆڵی ٥٨ مم، ٨٠ مم، A5 یان A4.'),
      L('Write a header and a footer, and choose whether the logo, the invoice '
              'barcode and the tax breakdown are printed.',
          'تكتب ترويسة وتذييلاً، وتختار طباعة الشعار وباركود الفاتورة وتفصيل '
              'الضريبة.',
          'سەردێڕ و پێدێڕ بنووسە، و هەڵبژێرە ئایا لۆگۆ و بارکۆدی پسوولە و '
              'وردەکاری باج چاپ دەکرێن.'),
      L('Open the cash drawer on printing, print automatically after a sale, '
              'and send a test print.',
          'تفتح الدرج عند الطباعة، وتطبع تلقائياً بعد البيع، وترسل طباعة '
              'تجريبية.',
          'دراوەرەکە لە کاتی چاپکردندا بکەرەوە، دوای فرۆشتن بە خۆکارانە چاپ '
              'بکە، و چاپێکی تاقیکردنەوە بنێرە.'),
      L('See a live preview of exactly what will come out.',
          'ترى معاينة حيّة لما سيخرج بالضبط.',
          'پێشبینینێکی زیندووی ئەوەی بەڕاستی دەردەچێت ببینە.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Connect a receipt printer', 'أوصّل طابعة وصولات',
            'چاپکەری پسوولە ببەستمەوە'),
        'printing',
      ),
      GuideTask(
        L('Make the cash drawer open by itself',
            'أجعل درج النقد يفتح تلقائياً',
            'وابکەم دراوەری پارە خۆی بکرێتەوە'),
        'printing',
        how: L('Edit the printer and switch "Open the cash drawer" on.',
            'عدّل الطابعة وشغّل «فتح درج النقد».',
            'چاپکەرەکە دەستکاری بکە و «کردنەوەی دراوەری پارە» هەڵبکە.'),
      ),
    ],
  ),

  GuideSection(
    id: 'users',
    icon: Icons.manage_accounts_outlined,
    groupKey: AppText.navGroupSystem,
    title: L('Users', 'المستخدمون', 'بەکارهێنەران'),
    purpose: L(
      'Who may sign in, and as what.',
      'من يستطيع الدخول، وبأي صفة.',
      'کێ دەتوانێت بچێتە ژوورەوە، و وەک چی.',
    ),
    canDo: <L>[
      L('Add a user with a name, a username and a password.',
          'تضيف مستخدماً باسم واسم دخول وكلمة مرور.',
          'بەکارهێنەرێک زیاد بکە بە ناو و ناوی بەکارهێنەر و وشەی نهێنی.'),
      L('Give them a role: owner, manager, cashier or accountant.',
          'تعطيه دوراً: مالك أو مدير أو كاشير أو محاسب.',
          'ڕۆڵێکی بدەرێ: خاوەن، بەڕێوەبەر، کاسەر یان ژمێریار.'),
      L('Reset a password, and switch a user off without deleting their '
              'history.',
          'تعيد ضبط كلمة مرور، وتوقف مستخدماً دون حذف سجله.',
          'وشەی نهێنی ڕێکبخەرەوە، و بەکارهێنەرێک بکوژێنەوە بەبێ سڕینەوەی '
              'مێژووەکەی.'),
      L('See when each of them last signed in.',
          'ترى آخر دخول لكل منهم.',
          'ببینە هەریەکەیان کەی دوایین جار چوونەتە ژوورەوە.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Add a new cashier', 'أضيف كاشيراً جديداً',
            'کاسەرێکی نوێ زیاد بکەم'),
        'users',
      ),
    ],
  ),

  GuideSection(
    id: 'permissions',
    icon: Icons.verified_user_outlined,
    groupKey: AppText.navGroupSystem,
    title: L('Permissions', 'الصلاحيات', 'دەسەڵاتەکان'),
    purpose: L(
      'What each role may do, switch by switch.',
      'ما يستطيعه كل دور، مفتاحاً مفتاحاً.',
      'هەر ڕۆڵێک چی دەتوانێت بکات، کلیل بە کلیل.',
    ),
    canDo: <L>[
      L('Allow or refuse each thing separately: using the till, giving a '
              'discount, selling below the floor, selling past a credit limit, '
              'taking returns, voiding an invoice.',
          'تسمح أو تمنع كل شيء على حدة: استخدام الصندوق، ومنح خصم، والبيع تحت '
              'الحد الأدنى، والبيع فوق سقف الدين، وقبول المرتجعات، وإلغاء '
              'فاتورة.',
          'ڕێگە بدە یان ڕێگە مەدە بە هەر شتێک بەجیا: بەکارهێنانی کاسە، دانی '
              'داشکاندن، فرۆشتن لە خوار کەمترین نرخ، فرۆشتن سەروو سنووری قەرز، '
              'وەرگرتنی گەڕاندنەوە، هەڵوەشاندنەوەی پسوولە.'),
      L('Control who sees costs, margins, profit, the books and the activity '
              'log.',
          'تتحكم بمن يرى التكاليف والهوامش والأرباح والدفاتر وسجل النشاط.',
          'کۆنترۆڵ بکە کێ تێچوو و قازانج و دەفتەرەکان و تۆماری چالاکی دەبینێت.'),
      L('Control who may edit items, adjust stock, run a stocktake, order from '
              'suppliers, set up offers, change the settings and manage users.',
          'تتحكم بمن يعدّل الأصناف ويسوّي المخزون ويجرد ويطلب من الموردين ويضع '
              'العروض ويغيّر الإعدادات ويدير المستخدمين.',
          'کۆنترۆڵ بکە کێ کاڵا دەستکاری دەکات، کۆگا ڕاست دەکاتەوە، ژماردن '
              'دەکات، لە دابینکەران داوا دەکات، ئۆفەر دادەنێت، ڕێکخستنەکان '
              'دەگۆڕێت و بەکارهێنەران بەڕێوە دەبات.'),
    ],
    tips: <L>[
      L('The owner\'s column is shown but locked. A shop that can lock itself '
              'out of its own books has a worse problem than a missing feature.',
          'عمود المالك معروض لكنه مقفل. المحل الذي يستطيع أن يقفل نفسه خارج '
              'دفاتره عنده مشكلة أسوأ من ميزة ناقصة.',
          'ستوونی خاوەن پیشان دەدرێت بەڵام داخراوە. ئەو دوکانەی دەتوانێت خۆی لە '
              'دەفتەرەکانی خۆی دەربخات کێشەیەکی خراپتری هەیە لە تایبەتمەندییەکی '
              'کەم.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Stop cashiers seeing the profit', 'أمنع الكاشيرين من رؤية الربح',
            'ڕێگە لە کاسەرەکان بگرم لە بینینی قازانج'),
        'permissions',
      ),
      GuideTask(
        L('Let a manager override a credit limit',
            'أسمح لمدير بتجاوز سقف الدين',
            'ڕێگە بە بەڕێوەبەرێک بدەم سنووری قەرز تێپەڕێنێت'),
        'permissions',
      ),
    ],
  ),

  GuideSection(
    id: 'audit',
    icon: Icons.history_toggle_off_outlined,
    groupKey: AppText.navGroupSystem,
    title: L('Activity log', 'سجل النشاط', 'تۆماری چالاکی'),
    purpose: L(
      'Who did what, and when. Sign-ins, sales, voids, price changes, stock '
          'adjustments, settings, backups.',
      'من فعل ماذا ومتى. الدخول والمبيعات والإلغاءات وتغيير الأسعار وتسويات '
          'المخزون والإعدادات والنسخ الاحتياطية.',
      'کێ چی کردووە و کەی. چوونەژوورەوە، فرۆشتن، هەڵوەشاندنەوە، گۆڕینی نرخ، '
          'ڕاستکردنەوەی کۆگا، ڕێکخستنەکان، پاڵپشتەکان.',
    ),
    canDo: <L>[
      L('Filter by action, by user and by period, and search the detail.',
          'تصفّي بالإجراء والمستخدم والفترة، وتبحث في التفاصيل.',
          'بە کردار و بەکارهێنەر و ماوە بپاڵێوە، و لە وردەکارییەکاندا بگەڕێ.'),
    ],
    tips: <L>[
      L('The log is written inside the same transaction as the action, so an '
              'action that was rolled back leaves no trace — and the log can '
              'never fail a sale.',
          'يُكتب السجل داخل معاملة الإجراء نفسه، فالإجراء الذي تراجع لا يترك '
              'أثراً — والسجل لا يمكن أن يُفشل بيعاً.',
          'تۆمارەکە لە هەمان مامەڵەی کردارەکەدا دەنووسرێت، بۆیە کردارێک کە '
              'گەڕێندراوەتەوە هیچ شوێنێک بەجێناهێڵێت — و تۆمارەکە هەرگیز '
              'ناتوانێت فرۆشتنێک شکست بهێنێت.'),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Find out who voided an invoice', 'أعرف من ألغى فاتورة',
            'بزانم کێ پسوولەیەکی هەڵوەشاندووەتەوە'),
        'audit',
      ),
    ],
  ),

  GuideSection(
    id: 'settings',
    icon: Icons.settings_outlined,
    groupKey: AppText.navGroupSystem,
    title: L('Settings', 'الإعدادات', 'ڕێکخستنەکان'),
    purpose: L(
      'The choices a shop makes once, and the three dangerous buttons.',
      'الخيارات التي يتّخذها المحل مرة واحدة، والأزرار الخطرة الثلاثة.',
      'ئەو هەڵبژاردنانەی دوکان یەک جار دەیکات، و سێ دوگمە مەترسیدارەکە.',
    ),
    parts: <GuidePart>[
      GuidePart(
        L('Business', 'المحل', 'دوکان'),
        L('The name, phone and address that appear on every receipt.',
            'الاسم والهاتف والعنوان التي تظهر على كل وصل.',
            'ئەو ناو و تەلەفۆن و ناونیشانەی لەسەر هەموو پسوولەیەک دەردەکەون.'),
      ),
      GuidePart(
        L('Currency and tax', 'العملة والضريبة', 'دراو و باج'),
        L('The symbol, how many decimals are shown, the rounding step for cash '
              'and for change, the default tax rate, and whether prices already '
              'include tax.',
            'الرمز وعدد الخانات العشرية وخطوة التقريب للنقد وللباقي ونسبة '
                'الضريبة الافتراضية وهل الأسعار شاملة للضريبة.',
            'هێما، چەند خانەی دەیی پیشان دەدرێت، پلەی خڕکردنەوە بۆ کاش و بۆ '
                'پاشماوە، ڕێژەی باجی بنەڕەتی، و ئایا نرخەکان باجیان تێدایە.'),
      ),
      GuidePart(
        L('Till', 'الصندوق', 'کاسە'),
        L('Default prices, selling below zero, printing automatically, asking '
              'for a sign-in, the scale label prefix, and refusing to sell '
              'below the minimum price.',
            'الأسعار الافتراضية، والبيع تحت الصفر، والطباعة التلقائية، وطلب '
                'تسجيل الدخول، وبادئة ملصق الميزان، ورفض البيع تحت الحد الأدنى.',
            'نرخە بنەڕەتییەکان، فرۆشتن لە خوار سفر، چاپی خۆکار، داواکردنی '
                'چوونەژوورەوە، پێشگری لەیبڵی تەرازوو، و ڕەتکردنەوەی فرۆشتن لە '
                'خوار کەمترین نرخ.'),
      ),
      GuidePart(
        L('Second currency', 'العملة الثانية', 'دراوی دووەم'),
        L('Accept dollars over the counter at a rate you set. Change always '
              'leaves the dinar drawer.',
            'استلم الدولار على الكاونتر بسعر تحدّده. والباقي يخرج دائماً من درج '
                'الدينار.',
            'دۆلار لەسەر کاونتەر وەربگرە بەو نرخەی دایدەنێیت. پاشماوە هەمیشە لە '
                'دراوەری دیناردا دەردەچێت.'),
      ),
      GuidePart(
        L('Cash shifts', 'ورديات الصندوق', 'شیفتەکانی سندوق'),
        L('Whether a drawer must be open before anything can be sold, and '
              'whether the Z report prints on closing.',
            'هل يجب فتح وردية قبل البيع، وهل يُطبع تقرير Z عند الإغلاق.',
            'ئایا دەبێت شیفت بکرێتەوە پێش فرۆشتن، و ئایا ڕاپۆرتی Z لە کاتی '
                'داخستندا چاپ دەکرێت.'),
      ),
      GuidePart(
        L('Points', 'النقاط', 'خاڵەکان'),
        L('What spend earns a point, what a point is worth, and how many are '
              'needed before they can be used.',
            'ما الإنفاق الذي يكسب نقطة، وكم تساوي النقطة، وكم يلزم قبل '
                'استخدامها.',
            'چەند خەرجکردن یەک خاڵ دەهێنێت، خاڵێک چەند دەبێت، و چەندیان پێویستە '
                'پێش بەکارهێنانیان.'),
      ),
      GuidePart(
        L('Customer display', 'شاشة الزبون', 'شاشەی کڕیار'),
        L('Switch it on, then open the address it shows in a browser on the '
              'second monitor and put it full screen. Turn on network access '
              'and a tablet on the counter can show it too.',
            'شغّلها، ثم افتح العنوان الذي تعرضه في متصفح على الشاشة الثانية '
                'واجعله ملء الشاشة. وبتشغيل الوصول عبر الشبكة يستطيع جهاز لوحي '
                'على الكاونتر عرضها أيضاً.',
            'هەڵیبکە، پاشان ئەو ناونیشانەی پیشانی دەدات لە وێبگەڕدا لەسەر '
                'شاشەی دووەم بکەرەوە و پڕ بە شاشە بیکە. بە هەڵکردنی '
                'دەستگەیشتنی تۆڕ تابلێتێکی سەر کاونتەریش دەتوانێت پیشانی '
                'بدات.'),
      ),
      GuidePart(
        L('Backups', 'النسخ الاحتياطية', 'پاڵپشتەکان'),
        L('Copy the database automatically every so many hours, keep the last '
              'few, and choose where they go.',
            'انسخ قاعدة البيانات تلقائياً كل عدة ساعات، واحتفظ بآخر بضع نسخ، '
                'واختر أين تذهب.',
            'بنکەدراوەکە بە خۆکارانە هەموو چەند کاتژمێرێک کۆپی بکە، دوایین چەند '
                'دانە هەڵبگرە، و هەڵبژێرە بۆ کوێ دەچن.'),
      ),
      GuidePart(
        L('Pictures', 'الصور', 'وێنەکان'),
        L('How much room the item photos take, and a broom for the ones no '
              'item points at any more.',
            'كم مساحة تشغلها صور الأصناف، ومكنسة لما لم يعد أي صنف يشير إليه.',
            'وێنەکانی کاڵا چەند شوێن دەگرن، و گسکێک بۆ ئەوانەی هیچ کاڵایەک '
                'ئاماژەیان پێ ناکات.'),
      ),
      GuidePart(
        L('Careful with these', 'كن حذراً مع هذه', 'ئاگاداربە لەمانە'),
        L('Back up now, restore from a copy, import the old database, and load '
              'the test catalogue.',
            'نسخ احتياطي الآن، واستعادة من نسخة، واستيراد قاعدة البيانات '
                'القديمة، وتحميل كتالوك الاختبار.',
            'ئێستا پاڵپشت بکە، لە کۆپییەک بگەڕێنەوە، بنکەدراوەی کۆن هاوردە بکە، '
                'و کاتالۆگی تاقیکردنەوە بار بکە.'),
      ),
    ],
    tasks: <GuideTask>[
      GuideTask(
        L('Change the shop name on the receipt',
            'أغيّر اسم المحل على الوصل',
            'ناوی دوکان لەسەر پسوولە بگۆڕم'),
        'settings',
      ),
      GuideTask(
        L('Accept dollars', 'أقبل الدولار', 'دۆلار وەربگرم'),
        'settings',
        how: L('Switch on "Accept a second currency" and set the rate.',
            'شغّل «قبول عملة ثانية» واضبط السعر.',
            '«وەرگرتنی دراوی دووەم» هەڵبکە و نرخەکە دابنێ.'),
      ),
      GuideTask(
        L('Protect my data', 'أحمي بياناتي', 'داتاکەم بپارێزم'),
        'settings',
        how: L('Switch automatic backups on and choose a folder — ideally on '
                'another drive.',
            'شغّل النسخ التلقائي واختر مجلداً — يفضّل على قرص آخر.',
            'پاڵپشتی خۆکار هەڵبکە و بوخچەیەک هەڵبژێرە — باشتر لەسەر '
                'دیسکێکی تر.'),
      ),
      GuideTask(
        L('Put a second screen in front of the customer',
            'أضع شاشة ثانية أمام الزبون',
            'شاشەیەکی دووەم لەبەردەم کڕیار دابنێم'),
        'settings',
      ),
    ],
  ),
];
