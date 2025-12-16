import 'package:flutter/material.dart';
import '../utils/ormoc_barangays.dart';

class SearchableDropdown extends StatefulWidget {
  final String? value;
  final String? labelText;
  final String? hintText;
  final IconData? prefixIcon;
  final ValueChanged<String?>? onChanged;
  final String? Function(String?)? validator;
  final List<String> items;
  final bool isSearchable;
  final bool enabled;

  const SearchableDropdown({
    super.key,
    this.value,
    this.labelText,
    this.hintText,
    this.prefixIcon,
    this.onChanged,
    this.validator,
    this.items = const [],
    this.isSearchable = true,
    this.enabled = true,
  });

  @override
  State<SearchableDropdown> createState() => _SearchableDropdownState();
}

class _SearchableDropdownState extends State<SearchableDropdown> {
  late TextEditingController _searchController;
  List<String> _filteredItems = [];
  bool _isExpanded = false;
  String? _selectedValue;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _selectedValue = widget.value;
    _filteredItems = widget.items;
  }

  @override
  void didUpdateWidget(SearchableDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _selectedValue = widget.value;
    }
    if (widget.items != oldWidget.items) {
      _filteredItems = widget.items;
      _searchController.clear();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterItems(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items;
      } else {
        _filteredItems = widget.items
            .where((item) => item.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _selectItem(String item) {
    setState(() {
      _selectedValue = item;
      _isExpanded = false;
      _searchController.clear();
      _filteredItems = widget.items;
    });
    widget.onChanged?.call(item);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dropdown trigger
        GestureDetector(
          onTap: widget.enabled ? () {
            setState(() {
              _isExpanded = !_isExpanded;
              if (_isExpanded) {
                _searchController.clear();
                _filteredItems = widget.items;
              }
            });
          } : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
              color: widget.enabled ? Colors.white : Colors.grey[200],
            ),
            child: Row(
              children: [
                if (widget.prefixIcon != null) ...[
                  Icon(
                    widget.prefixIcon,
                    color: widget.enabled ? Colors.grey[600] : Colors.grey[400],
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    _selectedValue ?? widget.hintText ?? 'Select an option',
                    style: TextStyle(
                      color: _selectedValue != null 
                          ? (widget.enabled ? Colors.black87 : Colors.grey[600])
                          : Colors.grey[500],
                      fontSize: 16,
                    ),
                  ),
                ),
                Icon(
                  _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: widget.enabled ? Colors.grey[600] : Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
        
        // Dropdown content
        if (_isExpanded) ...[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Search field
                if (widget.isSearchable && widget.items.length > 5)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onChanged: _filterItems,
                    ),
                  ),
                
                // Items list
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = _filteredItems[index];
                      final isSelected = item == _selectedValue;
                      
                      return InkWell(
                        onTap: () => _selectItem(item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue[50] : Colors.transparent,
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.grey[200]!,
                                width: index < _filteredItems.length - 1 ? 1 : 0,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item,
                                  style: TextStyle(
                                    color: isSelected ? Colors.blue[700] : Colors.black87,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check,
                                  color: Colors.blue[700],
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class SearchableBarangayDropdown extends StatelessWidget {
  final String? value;
  final String? labelText;
  final String? hintText;
  final IconData? prefixIcon;
  final ValueChanged<String?>? onChanged;
  final String? Function(String?)? validator;
  final bool enabled;

  const SearchableBarangayDropdown({
    super.key,
    this.value,
    this.labelText = 'Barangay',
    this.hintText = 'Select your barangay',
    this.prefixIcon = Icons.location_city,
    this.onChanged,
    this.validator,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SearchableDropdown(
      value: value,
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      onChanged: onChanged,
      validator: validator,
      items: OrmocBarangays.barangays,
      isSearchable: true,
      enabled: enabled,
    );
  }
}
