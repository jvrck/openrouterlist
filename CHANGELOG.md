# Changelog

## [0.0.3] - 2025-08-15
### Added
- **Model Capability Columns**: Added 5 new columns displaying model capabilities
  - Tool Calling (144 models supported)
  - Structured Outputs (142 models supported)
  - Reasoning (90 models supported)
  - Response Format (185 models supported)
  - Web Search (16 models supported)
- **Advanced Capability Filtering System**
  - Filter models by required capabilities with Match All/Match Any modes
  - Quick filter presets for common use cases (Agentic, Reasoning, Structured, Web-Enabled)
  - Visual indicators showing active filter count and matching models
  - Real-time filtering with DataTables integration
- **Enhanced Keyboard Shortcuts**
  - `c` - Focus capability filters
  - `m` - Toggle filter mode (Match All/Any)
  - `x` - Clear all capability filters
- **Improved URL State Management**
  - Capability filters are now persisted in URL for sharing
  - Filter mode preference saved in URL parameters

### Changed
- Updated `get_zipped.sh` script to extract capability data from OpenRouter API's `supported_parameters` field
- Card view now respects capability filters in addition to favorites
- Column visibility toggles extended to support new capability columns
- Mobile interface optimized for capability filter controls

### Technical
- Implemented custom DataTables search extension for capability filtering
- Added complex jq parsing logic for capability detection in bash script
- Enhanced state management to handle multiple filter types simultaneously

## [0.0.2] - 2025-08-15
### Added
- Dark/Light theme toggle with system preference detection
- Favorite models functionality with localStorage persistence
- Shareable URLs that preserve filter/search state
- Keyboard shortcuts for power users (/, f, t, d, v, e, ?, Esc)
- Mobile-responsive card view layout for better mobile experience
- Column show/hide customization options
- Density options (Compact/Comfortable/Spacious) for row heights
- Help modal showing all keyboard shortcuts
- Modern styled export buttons with icons

### Changed
- Updated color scheme from green to modern blue (#2563eb light, #3b82f6 dark)
- Improved dark mode with better contrast and visibility
- Modernized UI with smooth transitions and animations
- Enhanced DataTables button styling with icons and hover effects

### Fixed
- Dark mode table cell background colors now display correctly
- Density toggle functionality now properly changes table padding
- Text contrast improved in dark mode for better readability

## [0.0.1] - 2024-09-21
### Added
- Initial release of the project.
