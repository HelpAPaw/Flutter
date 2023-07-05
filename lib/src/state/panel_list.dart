// Expansion Panel List Widget: Item State
class PanelItem {
  bool isExpanded;
  int identity;

  PanelItem({
    required this.identity,
    this.isExpanded = false,
  });
}

List<PanelItem> generateItems(int numberOfItems) {
  return List<PanelItem>.generate(numberOfItems, (int index) {
    return PanelItem(
      identity: index,
    );
  });
}
