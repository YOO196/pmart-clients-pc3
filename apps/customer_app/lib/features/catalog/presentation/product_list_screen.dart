import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import 'product_list_view.dart';

/// 카테고리·진열 "전체보기"의 상품 목록.
class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key, required this.categoryId, this.title});

  final String categoryId;
  final String? title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title ?? '')),
    body: ProductListView(baseQuery: ProductQuery(categoryId: categoryId)),
  );
}
