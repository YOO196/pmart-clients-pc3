import 'package:flutter/material.dart';

import '../domain/catalog.dart';
import 'product_list_view.dart';

/// 카테고리·진열 "전체보기"의 상품 목록.
class ProductListScreen extends StatelessWidget {
  const ProductListScreen({
    super.key,
    required this.categoryId,
    this.title,
    this.onSale = false,
    this.keyword,
  });

  /// 검색어(검색 결과 "찾으시는 키워드의 할인 상품 전체 ›" — 초안 16 B).
  final String? keyword;

  final String categoryId;
  final String? title;

  /// 할인 상품만(카테고리 [할인] 타일, BR-82). 이때 categoryId 는 비어 있어 모든 카테고리.
  final bool onSale;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title ?? '')),
    body: ProductListView(
      baseQuery: ProductQuery(
        categoryId: categoryId.isEmpty ? null : categoryId,
        keyword: keyword,
        onSale: onSale,
      ),
    ),
  );
}
