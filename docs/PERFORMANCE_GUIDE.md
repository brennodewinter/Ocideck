# OciDeck — Performance Guide

This document outlines performance considerations, optimization strategies, and best practices for using and developing with OciDeck.

## Overview

OciDeck is designed to handle presentations efficiently while maintaining responsive user experience. Understanding the performance characteristics helps users optimize their workflows and developers create efficient extensions.

## Memory Management

### Image Handling
- Images are decoded with memory limits to prevent out-of-memory errors
- Large images are capped at a maximum resolution for preview purposes  
- Animated GIF/WebP support with frame rate limiting
- Capped memory usage for image processing operations

### Asset Storage
- Project assets are stored in dedicated folders with organized structure
- Assets outside project directories cannot be referenced (security feature)
- Memory-limited caching strategy for web builds

## Rendering Performance

### Slide Preview and Presentation
- Slides render as Flutter widgets for preview and presentation
- Mermaid diagrams rendered to inline SVG via shared WebView
- Charts use `fl_chart` library optimized for performance  
- Video playback through shared `_MediaPlaybackHost`

### Export Performance
- PDF/PPTX exports are rasterized to images (SlideRasterizer)
- HTML export pre-renders charts to inline SVG in Dart
- Export process is optimized for memory usage and speed

## Large Presentation Handling

### Slide Limits
- While OciDeck can technically handle large presentations, performance may degrade with:
  - Over 100 slides
  - Complex chart visualizations (10+ data series)
  - High-resolution media assets
  - Many interactive elements (questions, timelines)

### Optimization Recommendations
- Break large presentations into smaller decks when possible
- Use image compression for high-resolution photos  
- Optimize chart complexity (fewer series, simpler visuals)
- Reduce the number of video segments in timeline slides

## Export Performance Considerations

### PDF/PPTX Exports
- Rasterization process impacts export time for complex slides
- Chart rendering affects performance due to SVG generation
- Large presentations may take longer to process and render  

### HTML Exports  
- Self-contained exports with embedded assets
- JavaScript libraries are bundled but optimized (minified versions)
- Performance impact from chart rendering in browser

## System Resource Usage

### CPU Usage
- Background processing for asset handling and privacy scanning
- Real-time video playback during preview/presentation
- Memory-intensive operations: image decoding, chart generation

### Memory Usage  
- Preview and presentation consume more memory than editor mode
- Large media files require substantial RAM allocation
- Web builds have memory limitations due to browser constraints

## Development Performance Guidelines

### For Developers
1. **Code Size Limits**: Methods should not exceed 150 lines (check_method_length)
2. **Memory Efficiency**: Avoid unnecessary object creation during rendering loops  
3. **Asynchronous Operations**: Long-running tasks use proper async patterns
4. **Caching Strategies**: Use LRU cache for frequently accessed data
5. **Layer Separation**: Services should not import UI layers directly

### Testing Performance
- Widget and export tests cover the performance-critical rendering/export paths
  for correctness
- Image memory-cap behaviour is covered by dedicated tests
- No dedicated timing/throughput benchmarks are run in CI — profile manually
  (Flutter DevTools) when investigating a specific slowdown

## Best Practices for Users

### Creating Efficient Presentations
1. **Image Optimization**:
   - Use appropriate image resolutions (don't use 4K photos at 50% scale)
   - Compress images before import when possible
   - Consider using thumbnail versions for slides with multiple images

2. **Chart Design**:
   - Limit data series to 5-10 maximum for readability
   - Use simpler chart types where complex ones aren't necessary  
   - Minimize the number of charts on each slide

3. **Media Management**:
   - Use shorter video segments rather than long clips
   - Consider using lower resolution videos when full quality isn't needed
   - Implement proper trimming for video across slides

4. **Slide Organization**:
   - Group similar content in sections to improve navigation  
   - Avoid excessive animations or complex transitions
   - Keep slide text concise and focused

### Performance Monitoring
- Monitor memory usage through system tools during large operations
- Consider upgrading hardware if consistently hitting resource limits
- Use crash recovery features for long editing sessions

## Benchmarking Information

### Typical Performance Metrics

The figures below are **rough indicative ranges** to set expectations, not
measured benchmarks — actual timings depend heavily on hardware, slide content,
and platform (desktop vs web).

| Operation | Time Range | Notes |
|-----------|------------|-------|
| Slide Preview Load | < 100ms | For simple slides |
| Complex Chart Render | 50-300ms | Varies by data complexity |
| PDF Export | 2-30 seconds | Depends on slide count and complexity |
| PPTX Export | 3-60 seconds | Similar to PDF but with different overhead |
| HTML Export | 1-10 seconds | Usually faster than other formats |

### Performance Testing
OciDeck does not ship a formal timing/benchmark suite. Performance is guarded
indirectly: the widget/export tests exercise the rendering and export paths for
correctness (so a regression that breaks them is caught), and behaviours such as
the image memory caps have dedicated tests. There are no automated wall-clock or
throughput benchmarks in CI, so the ranges above should be treated as guidance
rather than enforced budgets.

## Known Limitations and Workarounds

### Browser Version Considerations
- Web builds have memory constraints compared to desktop versions
- Performance is limited by browser capabilities
- Large presentations may cause browser instability or timeouts

### Desktop Optimization
- Desktop versions can utilize system resources more effectively  
- Caching strategies are more robust on local filesystems
- Better handling of large media assets

## Future Improvements

### Planned Optimizations
1. **Lazy Loading**: Slides will be loaded only when needed during presentation
2. **Advanced Caching**: More sophisticated memory management for asset caching
3. **Parallel Processing**: Multi-threaded operations where possible  
4. **Memory Profiling Tools**: Built-in tools to help identify performance bottlenecks

## Troubleshooting Performance Issues

### Common Symptoms and Solutions
1. **Slow Preview/Rendering**:
   - Check if slide has complex charts or animations
   - Reduce image resolution for large slides  

2. **High Memory Usage**:
   - Close unnecessary tabs  
   - Break large presentations into smaller decks
   - Clear temporary files from system

3. **Export Time Too Long**: 
   - Simplify chart complexity in presentation
   - Remove excessive media elements
   - Export to PDF/PPTX individually if needed  

### Diagnostic Tools
- Built-in performance monitoring (coming soon)
- Memory usage indicators during operations  
- Speed profiling for rendering tasks

## Compatibility Notes

The performance characteristics may vary based on:
- Hardware specifications (CPU, RAM, storage type)
- Operating system optimizations 
- Browser version and capabilities (web builds only) 
- Network conditions (for remote content or services)

This guide provides the baseline understanding of OciDeck's performance characteristics to help optimize both user experience and developer efficiency.