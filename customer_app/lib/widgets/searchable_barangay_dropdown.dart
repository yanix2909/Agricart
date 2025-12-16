import 'package:flutter/material.dart';
import '../utils/ormoc_barangays.dart';

class SearchableBarangayDropdown extends StatefulWidget {
  final String? value;
  final String? labelText;
  final String? hintText;
  final IconData? prefixIcon;
  final Function(String?) onChanged;
  final String? Function(String?)? validator;

  const SearchableBarangayDropdown({
    super.key,
    this.value,
    this.labelText,
    this.hintText,
    this.prefixIcon,
    required this.onChanged,
    this.validator,
  });

  @override
  State<SearchableBarangayDropdown> createState() => _SearchableBarangayDropdownState();
}

class _SearchableBarangayDropdownState extends State<SearchableBarangayDropdown> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _filteredBarangays = [];
  bool _isExpanded = false;
  String? _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.value;
    _filteredBarangays = OrmocBarangays.barangays;
    if (_selectedValue != null) {
      _searchController.text = _selectedValue!;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SearchableBarangayDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _selectedValue = widget.value;
      _searchController.text = _selectedValue ?? '';
    }
  }

  void _filterBarangays(String query) {
    setState(() {
      _filteredBarangays = OrmocBarangays.searchBarangays(query);
    });
  }

  void _selectBarangay(String barangay) {
    setState(() {
      _selectedValue = barangay;
      _searchController.text = barangay;
      _isExpanded = false;
    });
    widget.onChanged(barangay);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.labelText != null)
          Text(
            widget.labelText!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
        if (widget.labelText != null) const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              TextFormField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  prefixIcon: widget.prefixIcon != null ? Icon(widget.prefixIcon) : null,
                  suffixIcon: Icon(
                    _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onTap: () {
                  setState(() {
                    _isExpanded = true;
                  });
                },
                onChanged: _filterBarangays,
                validator: widget.validator,
              ),
              if (_isExpanded)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filteredBarangays.length,
                    itemBuilder: (context, index) {
                      final barangay = _filteredBarangays[index];
                      final isSelected = _selectedValue == barangay;
                      
                      return InkWell(
                        onTap: () => _selectBarangay(barangay),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue[50] : Colors.transparent,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  barangay,
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
        // Overlay to close dropdown when tapping outside
        if (_isExpanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isExpanded = false;
                });
              },
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
      ],
    );
  }
}
