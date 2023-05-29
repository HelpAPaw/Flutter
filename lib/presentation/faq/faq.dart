import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class FAQSScreen extends StatelessWidget {
  const FAQSScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _BuildFAQAppBar(),
      body: const _BuildFAQBody(),
    );
  }
}

class _BuildFAQAppBar extends StatelessWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      centerTitle: true,
      leading: IconButton(
        color: Colors.white,
        onPressed: () {
          Navigator.pop(context);
        },
        icon: const Icon(Icons.arrow_back),
      ),
      title: const Text(
        'FAQs',
        style: TextStyle(
          fontSize: 20.0,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _BuildFAQBody extends StatelessWidget {
  const _BuildFAQBody();

  @override
  Widget build(BuildContext context) {
    final widthSize = MediaQuery.of(context).size.width;
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.symmetric(horizontal: widthSize * 0.05),
        children: faqsData
            .map(
              (item) => _BuildFAQItem(
                title: item['title'],
                content: item['content'],
              ),
            )
            .toList(),
      ),
    );
  }
}

class _BuildFAQItem extends StatelessWidget {
  final String? title;
  final String? content;
  const _BuildFAQItem({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${" " * 2} $title',
            style: const TextStyle(
              fontSize: 18,
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Text(
            content!,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }
}

final List<Map<String, dynamic>> faqsData = [
  {
    'title': 'faq_title_1'.tr(),
    'content': 'faq_content1'.tr(),
  },
  {
    'title': 'faq_title_2'.tr(),
    'content': 'faq_content2'.tr(),
  },
  {
    'title': 'faq_title_3'.tr(),
    'content': 'faq_content3'.tr(),
  },
  {
    'title': 'faq_title_4'.tr(),
    'content': 'faq_content4'.tr(),
  },
];
