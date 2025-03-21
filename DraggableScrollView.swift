import SwiftUI

/// A customizable scroll view that supports both vertical and horizontal scrolling with inertia and bounce effects.
/// This view provides a more native-feeling scroll experience with customizable physics parameters.
public struct DraggableScrollView<Content: View>: View {
    // MARK: - Types
    
    private struct ScrollViewSizeInfo {
        let size: CGSize
        let scrollViewId: UUID
        let axes: Axis.Set
        
        var isHorizontal: Bool {
            axes.contains(.horizontal) && !axes.contains(.vertical)
        }
        
        var isVertical: Bool {
            axes.contains(.vertical) && !axes.contains(.horizontal)
        }
    }
    
    // MARK: - Properties
    
    /// Unique identifier for this scroll view instance
    private let id = UUID()
    
    /// Scroll direction
    public var axes: Axis.Set
    
    /// Whether to show indicators
    public var showsIndicators: Bool
    
    /// The content of the scroll view
    public var content: () -> Content

    @State private var contentSize: CGSize = .zero
    @State private var viewportSize: CGSize = .zero
    
    @State private var dragOffset: CGSize = .zero
    @State private var lastDragPosition: CGSize = .zero
    @State private var lastUpdateTime: Date = Date()
    @State private var velocity: CGSize = .zero
    @State private var isAnimating = false
    @State private var accumulatedOffset: CGSize = .zero
    @State private var geometryInitialized: Bool = false
    
    // Bounce coefficient (0-1), lower value gives stronger bounce effect
    private let bounceCoefficient: CGFloat = 0.2
    
    // Default horizontal content estimation for demo layout
    private let defaultCardWidth: CGFloat = 150.0
    private let defaultCardSpacing: CGFloat = 20.0
    private let defaultCardCount: CGFloat = 20.0
    private let defaultHorizontalPadding: CGFloat = 40.0
    
    // Default vertical content estimation
    private let defaultItemHeight: CGFloat = 100.0
    private let defaultItemSpacing: CGFloat = 20.0
    private let defaultItemCount: CGFloat = 30.0
    private let defaultVerticalPadding: CGFloat = 40.0
    
    @State private var lastValidHorizontalWidth: CGFloat = 0
    @State private var lastValidVerticalHeight: CGFloat = 0
    
    private func notificationName(for type: String) -> Notification.Name {
        return Notification.Name("\(type)_\(id.uuidString)")
    }
    
    private struct ContentSizeModifier: ViewModifier {
        let scrollViewId: UUID
        let axes: Axis.Set
        
        func body(content: Content) -> some View {
            content
                .background(
                    GeometryReader { contentGeometry in
                        Color.clear
                            .preference(
                                key: ContentSizePreferenceKey.self,
                                value: ScrollViewSizeInfo(
                                    size: contentGeometry.size,
                                    scrollViewId: scrollViewId,
                                    axes: axes
                                )
                            )
                            .onAppear {
                                // Immediately report content size - critical for correct scrolling
                                let size = contentGeometry.size
                                print("Content appeared with size: \(size)")
                            }
                    }
                )
                .background(
                    GeometryReader { backgroundGeometry in
                        Color.clear
                    }
                )
        }
    }

    private struct ContentSizePreferenceKey: PreferenceKey {
        static var defaultValue = ScrollViewSizeInfo(size: .zero, scrollViewId: UUID(), axes: [])
        
        static func reduce(value: inout ScrollViewSizeInfo, nextValue: () -> ScrollViewSizeInfo) {
            let newValue = nextValue()
            
            // Only update if axes configuration matches
            if value.axes.isEmpty || 
               (value.isHorizontal == newValue.isHorizontal && value.isVertical == newValue.isVertical) {
                value = newValue
                print("Content size preference changed: \(value.size)")
            }
        }
    }

    private struct SizePreferenceKey: PreferenceKey {
        static var defaultValue = ScrollViewSizeInfo(size: .zero, scrollViewId: UUID(), axes: [])
        
        static func reduce(value: inout ScrollViewSizeInfo, nextValue: () -> ScrollViewSizeInfo) {
            let newValue = nextValue()
            
            if newValue.size.width > 0 || newValue.size.height > 0 {
                // Only update if axes configuration matches
                if value.axes.isEmpty || 
                   (value.isHorizontal == newValue.isHorizontal && value.isVertical == newValue.isVertical) {
                    value = newValue
                    print("MeasureSize detected: \(value.size)")
                }
            }
        }
    }

    private extension View {
        func measureSize(
            scrollViewId: UUID,
            axes: Axis.Set,
            perform action: @escaping (CGSize) -> Void
        ) -> some View {
            self.background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: SizePreferenceKey.self,
                            value: ScrollViewSizeInfo(
                                size: geometry.size,
                                scrollViewId: scrollViewId,
                                axes: axes
                            )
                        )
                        .onPreferenceChange(SizePreferenceKey.self) { sizeInfo in
                            if sizeInfo.size.width > 0 || sizeInfo.size.height > 0 {
                                action(sizeInfo.size)
                            }
                        }
                }
            )
        }
    }

    // MARK: - Initialization
    /// Creates a new DraggableScrollView.
    /// - Parameters:
    ///   - axes: The scroll directions to enable. Defaults to both vertical and horizontal.
    ///   - showsIndicators: Whether to show scroll indicators. Defaults to true.
    ///   - content: A closure returning the scroll view's content.
    public init(
        axes: Axis.Set = [.vertical, .horizontal],
        showsIndicators: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.content = content
    }

    // MARK: - Body
    public var body: some View {
        GeometryReader { geometry in
            ScrollView(axes, showsIndicators: showsIndicators) {
                ZStack(alignment: .topLeading) {
                    // Invisible frame to establish minimum content size
                    Rectangle()
                        .frame(
                            width: axes.contains(.horizontal) ? max(1000, geometry.size.width * 1.5) : nil,
                            height: axes.contains(.vertical) ? max(1000, geometry.size.height * 1.5) : nil
                        )
                        .opacity(0)
                        .measureSize(scrollViewId: id, axes: axes) { size in
                            // Handle minimum size updates if needed
                            print("[\(axes)] UUID: \(id) - Minimum size frame measured: \(size)")
                        }
                    
                    // Actual content
                    content()
                        .modifier(ContentSizeModifier(scrollViewId: id, axes: axes))
                }
                .background(
                    GeometryReader { scrollGeometry in
                        Color.clear
                            .measureSize(scrollViewId: id, axes: axes) { size in
                                print("\n=== ScrollView Content Frame ===")
                                print("[\(axes)] UUID: \(id)")
                                print("[\(axes)] ScrollView content frame measured: \(size)")
                                print("[\(axes)] Frame in local: \(scrollGeometry.frame(in: .local))")
                                print("[\(axes)] Frame in global: \(scrollGeometry.frame(in: .global))")
                                print("=== ScrollView Content Frame End ===\n")
                            }
                    }
                )
                .offset(
                    x: calculateOffset(for: .horizontal, in: geometry),
                    y: calculateOffset(for: .vertical, in: geometry)
                )
            }
            .gesture(createDragGesture())
            .onAppear {
                self.viewportSize = geometry.size
                self.geometryInitialized = true
                
                print("View appeared with viewport size: \(geometry.size)")
                
                // Apply immediate estimate to ensure we have some content size
                self.forceMeasureContentSize()
                
                // Double-check and estimate again after a short delay if needed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // If content size is still invalid, force estimate again
                    if (axes.contains(.horizontal) && contentSize.width <= 0) ||
                       (axes.contains(.vertical) && contentSize.height <= 0) {
                        print("Content size still invalid after delay, forcing measurement")
                        self.forceMeasureContentSize()
                    }
                    
                    print("Final content size after appear: \(contentSize)")
                }
                
                // Refresh geometry after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.viewportSize = geometry.size
                }
            }
            .onDisappear {
                // No need for notification cleanup anymore
            }
            .onPreferenceChange(ContentSizePreferenceKey.self) { sizeInfo in
                // Verify this is for the correct ScrollView
                guard sizeInfo.scrollViewId == id else { return }
                
                // Verify axes configuration matches
                let isCurrentHorizontal = axes.contains(.horizontal) && !axes.contains(.vertical)
                guard isCurrentHorizontal == sizeInfo.isHorizontal else { return }
                
                updateContentSize(with: sizeInfo.size, from: "PreferenceChange")
            }
        }
    }

    // MARK: - Private Methods
    
    private func createDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                handleDragChange(value)
            }
            .onEnded { value in
                handleDragEnd(value)
            }
    }
    
    private func handleDragChange(_ value: DragGesture.Value) {
        let translation = value.translation
        let shouldAllowHorizontalScroll = axes.contains(.horizontal)
        let shouldAllowVerticalScroll = axes.contains(.vertical)
        
        dragOffset = CGSize(
            width: shouldAllowHorizontalScroll ? translation.width : 0,
            height: shouldAllowVerticalScroll ? translation.height : 0
        )
        
        updateVelocity(translation: translation)
        lastDragPosition = translation
        lastUpdateTime = Date()
    }
    
    private func handleDragEnd(_ value: DragGesture.Value) {
        accumulatedOffset.width += dragOffset.width
        accumulatedOffset.height += dragOffset.height
        
        handleBounceBackIfNeeded()
        
        dragOffset = .zero
        lastDragPosition = .zero
        
        let hasSignificantHorizontalVelocity = axes.contains(.horizontal) && abs(velocity.width) > minimumVelocity
        let hasSignificantVerticalVelocity = axes.contains(.vertical) && abs(velocity.height) > minimumVelocity
        
        if hasSignificantHorizontalVelocity || hasSignificantVerticalVelocity {
            startInertiaAnimation()
        } else {
            velocity = .zero
        }
    }

    // Force content size measurement as a last resort
    private func forceMeasureContentSize() {
        print("\n=== Force Measure Content Size ===")
        print("[\(axes)] UUID: \(id)")
        print("[\(axes)] Current content size: \(contentSize)")
        print("[\(axes)] Current viewport size: \(viewportSize)")
        
        // For horizontal scrolling, use a more aggressive estimate
        if axes.contains(.horizontal) {
            // For horizontal scroll with cards, we can make a reasonable estimate
            let estimatedItemWidth: CGFloat = defaultCardWidth
            let estimatedSpacing: CGFloat = defaultCardSpacing
            let estimatedItems: CGFloat = defaultCardCount
            let estimatedPadding: CGFloat = defaultHorizontalPadding
            
            let estimatedContentWidth = (estimatedItemWidth * estimatedItems) + 
                                       (estimatedSpacing * (estimatedItems - 1)) + 
                                       estimatedPadding
                                       
            print("[\(axes)] Using forced estimated horizontal content width: \(estimatedContentWidth)")
            
            // Only update if the new estimate is larger than current width
            if estimatedContentWidth > contentSize.width {
                print("[\(axes)] Updating width from \(contentSize.width) to \(estimatedContentWidth)")
                contentSize.width = estimatedContentWidth
                lastValidHorizontalWidth = estimatedContentWidth
            } else {
                print("[\(axes)] Keeping current width: \(contentSize.width)")
            }
        }
        
        // For vertical scrolling, use a more aggressive estimate
        if axes.contains(.vertical) {
            // For vertical scrolling, similar approach
            let estimatedItemHeight: CGFloat = defaultItemHeight
            let estimatedSpacing: CGFloat = defaultItemSpacing
            let estimatedItems: CGFloat = defaultItemCount
            let estimatedPadding: CGFloat = defaultVerticalPadding
            
            let estimatedContentHeight = (estimatedItemHeight * estimatedItems) + 
                                        (estimatedSpacing * (estimatedItems - 1)) + 
                                        estimatedPadding
                                        
            print("[\(axes)] Using forced estimated vertical content height: \(estimatedContentHeight)")
            
            // Only update if the new estimate is larger than current height
            if estimatedContentHeight > contentSize.height {
                print("[\(axes)] Updating height from \(contentSize.height) to \(estimatedContentHeight)")
                contentSize.height = estimatedContentHeight
                lastValidVerticalHeight = estimatedContentHeight
            } else {
                print("[\(axes)] Keeping current height: \(contentSize.height)")
            }
        }
        
        print("[\(axes)] Final content size after force measure: \(contentSize)")
        print("=== Force Measure Content Size End ===\n")
    }
    
    // Calculate actual offset with bounce effect
    private func calculateOffset(for axis: Axis, in geometry: GeometryProxy) -> CGFloat {
        print("\n=== Calculate Offset ===")
        print("[\(axes)] UUID: \(id)")
        print("[\(axes)] Calculating offset for axis: \(axis)")
        print("[\(axes)] Current content size: \(contentSize)")
        print("[\(axes)] Current viewport size: \(viewportSize)")
        print("[\(axes)] Current accumulated offset: \(accumulatedOffset)")
        print("[\(axes)] Current drag offset: \(dragOffset)")
        
        // Check if scrolling is allowed for this axis
        switch axis {
        case .horizontal:
            if !axes.contains(.horizontal) {
                print("[\(axes)] Horizontal scrolling not allowed")
                return 0
            }
        case .vertical:
            if !axes.contains(.vertical) {
                print("[\(axes)] Vertical scrolling not allowed")
                return 0
            }
        }
        
        let currentOffset: CGFloat
        let contentLength: CGFloat
        let viewportLength: CGFloat
        
        switch axis {
        case .horizontal:
            currentOffset = accumulatedOffset.width + dragOffset.width
            contentLength = contentSize.width
            viewportLength = geometry.size.width
        case .vertical:
            currentOffset = accumulatedOffset.height + dragOffset.height
            contentLength = contentSize.height
            viewportLength = geometry.size.height
        }
        
        print("[\(axes)] Offset calculation:")
        print("  - Current offset: \(currentOffset)")
        print("  - Content length: \(contentLength)")
        print("  - Viewport length: \(viewportLength)")
        
        // If content size is invalid, allow free scrolling but apply bounce effect
        if contentLength <= 0 || viewportLength <= 0 {
            // Use smaller bounce coefficient for freer scrolling
            let softBounceCoefficient: CGFloat = 0.8
            print("[\(axes)] Invalid dimensions, using soft bounce: \(currentOffset * softBounceCoefficient)")
            return currentOffset * softBounceCoefficient
        }
        
        // CRITICAL: For horizontal scrolling, even if content is slightly smaller than viewport,
        // we should still allow full scrolling to show all content
        let horizontalScrollingMargin: CGFloat = 20.0
        let verticalScrollingMargin: CGFloat = 20.0
        
        // Determine if content should be considered smaller than viewport
        let isContentSmallerThanViewport: Bool
        switch axis {
        case .horizontal:
            isContentSmallerThanViewport = contentLength > 0 && 
                contentLength < (viewportLength - horizontalScrollingMargin)
            print("[\(axes)] Horizontal content smaller check: \(isContentSmallerThanViewport) (content: \(contentLength) vs viewport: \(viewportLength))")
        case .vertical:
            isContentSmallerThanViewport = contentLength > 0 && 
                contentLength < (viewportLength - verticalScrollingMargin)
            print("[\(axes)] Vertical content smaller check: \(isContentSmallerThanViewport) (content: \(contentLength) vs viewport: \(viewportLength))")
        }
        
        // If content is smaller than viewport, apply elastic effect with stronger resistance
        if isContentSmallerThanViewport {
            // For smaller content, allow scrolling but with stronger bounce back effect
            let smallContentBounceCoefficient: CGFloat = 0.6
            print("[\(axes)] Small content bounce: \(currentOffset * smallContentBounceCoefficient)")
            return currentOffset * smallContentBounceCoefficient
        }
        
        // Boundary definitions
        let maxOffset: CGFloat
        let minOffset: CGFloat
        
        switch axis {
        case .horizontal:
            maxOffset = 0.0  // Left boundary
            // If content width is close to viewport width, treat it as equal or larger
            let effectiveContentLength = contentLength < viewportLength ? 
                viewportLength - horizontalScrollingMargin : contentLength
            minOffset = viewportLength - effectiveContentLength  // Right boundary (negative)
            print("[\(axes)] Horizontal boundaries - maxOffset: \(maxOffset), minOffset: \(minOffset)")
        case .vertical:
            maxOffset = 0.0  // Top boundary
            minOffset = viewportLength - contentLength  // Bottom boundary (negative)
            print("[\(axes)] Vertical boundaries - maxOffset: \(maxOffset), minOffset: \(minOffset)")
        }
        
        // Apply bounce effect when exceeding boundaries
        if currentOffset > maxOffset {
            let overscroll = currentOffset - maxOffset
            let bounceOffset = maxOffset + (overscroll * bounceCoefficient)
            print("[\(axes)] Overscroll at max boundary: \(bounceOffset)")
            return bounceOffset
        } else if currentOffset < minOffset {
            let overscroll = minOffset - currentOffset
            let bounceOffset = minOffset - (overscroll * bounceCoefficient)
            print("[\(axes)] Overscroll at min boundary: \(bounceOffset)")
            return bounceOffset
        }
        
        print("[\(axes)] Final calculated offset: \(currentOffset)")
        print("=== Calculate Offset End ===\n")
        return currentOffset
    }

    // Handle boundary bounce back
    private func handleBounceBackIfNeeded() {
        let totalOffsetX = accumulatedOffset.width + dragOffset.width
        let totalOffsetY = accumulatedOffset.height + dragOffset.height
        
        print("\n[\(axes)] --- Handling Boundary Bounce ---")
        print("[\(axes)] totalOffsetX = \(totalOffsetX), totalOffsetY = \(totalOffsetY)")
        print("[\(axes)] contentSize = \(contentSize), viewportSize = \(viewportSize)")
        
        // If content size is not valid, force measurement before boundary handling
        if (contentSize.width <= 0 && axes.contains(.horizontal)) ||
           (contentSize.height <= 0 && axes.contains(.vertical)) {
            print("[\(axes)] Content size invalid before boundary handling, forcing measurement")
            forceMeasureContentSize()
            print("[\(axes)] Updated content size: \(contentSize)")
        }
        
        // If content size is still not ready after forcing measurement, skip boundary bounce handling
        if contentSize.width <= 0 || contentSize.height <= 0 || 
           viewportSize.width <= 0 || viewportSize.height <= 0 {
            print("[\(axes)] Content or viewport size not ready, skipping boundary handling")
            return
        }
        
        // For horizontal and vertical scrolling, we should allow scrolling when the axis is enabled
        let shouldAllowHorizontalScroll = axes.contains(.horizontal)
        let shouldAllowVerticalScroll = axes.contains(.vertical)
        
        // CRITICAL: For horizontal scrolling, even if content is slightly smaller than viewport,
        // we should still allow full scrolling to show all content
        let horizontalScrollingMargin: CGFloat = 20.0
        let verticalScrollingMargin: CGFloat = 20.0
        
        // We consider content smaller only if it's significantly smaller than viewport
        let contentSmallerThanViewportHorizontally = contentSize.width > 0 && 
            contentSize.width < (viewportSize.width - horizontalScrollingMargin)
        let contentSmallerThanViewportVertically = contentSize.height > 0 && 
            contentSize.height < (viewportSize.height - verticalScrollingMargin)
        
        print("[\(axes)] Allow scroll: horizontal=\(shouldAllowHorizontalScroll), vertical=\(shouldAllowVerticalScroll)")
        print("[\(axes)] Content smaller than viewport (with margin): horizontal=\(contentSmallerThanViewportHorizontally), vertical=\(contentSmallerThanViewportVertically)")
        
        // Calculate content boundaries for horizontal scrolling
        let maxOffsetX = 0.0  // Left edge boundary
        
        // If content width is close to viewport width, treat it as equal or larger
        let effectiveContentWidth = contentSmallerThanViewportHorizontally ? 
            viewportSize.width - horizontalScrollingMargin : contentSize.width
        
        let minOffsetX = viewportSize.width - effectiveContentWidth  // Right boundary (negative)
        
        print("[\(axes)] Boundaries: viewportSize = \(viewportSize.width), effectiveContentWidth = \(effectiveContentWidth)")
        
        // For vertical scrolling (remains unchanged)
        let maxOffsetY = 0.0  // Top boundary
        let minOffsetY = viewportSize.height - contentSize.height  // Bottom boundary (negative)
        
        print("[\(axes)] Boundaries: maxOffsetX = \(maxOffsetX)")
        print("[\(axes)]   minOffsetX = \(minOffsetX), minOffsetY = \(minOffsetY)")
        
        withAnimation(.bouncy) {
            // Handle horizontal direction
            if axes.contains(.horizontal) {
                if contentSmallerThanViewportHorizontally {
                    // Content is smaller than viewport - allow offset but apply damping for bounce-back
                    if abs(totalOffsetX) > 100 {
                        print("[\(axes)] Horizontal: content smaller than viewport, large offset, strong damping")
                        accumulatedOffset.width = totalOffsetX * 0.5
                        if abs(accumulatedOffset.width) < 1.0 {
                            accumulatedOffset.width = 0
                        }
                    } else if abs(totalOffsetX) > 50 {
                        print("[\(axes)] Horizontal: content smaller than viewport, medium offset, medium damping")
                        accumulatedOffset.width = totalOffsetX * 0.7
                    } else {
                        print("[\(axes)] Horizontal: content smaller than viewport, small offset, light damping")
                        accumulatedOffset.width = totalOffsetX * 0.9
                    }
                } else {
                    // Apply boundary constraints for content larger than viewport
                    if totalOffsetX > maxOffsetX {
                        print("[\(axes)] Horizontal: exceeds left edge, resetting to \(maxOffsetX)")
                        accumulatedOffset.width = maxOffsetX
                    } else if totalOffsetX < minOffsetX {
                        print("[\(axes)] Horizontal: exceeds right edge, resetting to \(minOffsetX)")
                        accumulatedOffset.width = minOffsetX
                    } else {
                        print("[\(axes)] Horizontal: within boundaries, keeping offset \(accumulatedOffset.width)")
                    }
                }
            } else {
                if accumulatedOffset.width != 0 {
                    print("[\(axes)] Horizontal scrolling not allowed, resetting offset to 0")
                    accumulatedOffset.width = 0
                }
            }
            
            // Handle vertical direction
            if axes.contains(.vertical) {
                if contentSmallerThanViewportVertically {
                    // Content is smaller than viewport - allow offset but apply damping for bounce-back
                    if abs(totalOffsetY) > 100 {
                        print("[\(axes)] Vertical: content smaller than viewport, large offset, strong damping")
                        accumulatedOffset.height = totalOffsetY * 0.5
                        if abs(accumulatedOffset.height) < 1.0 {
                            accumulatedOffset.height = 0
                        }
                    } else if abs(totalOffsetY) > 50 {
                        print("[\(axes)] Vertical: content smaller than viewport, medium offset, medium damping")
                        accumulatedOffset.height = totalOffsetY * 0.7
                    } else {
                        print("[\(axes)] Vertical: content smaller than viewport, small offset, light damping")
                        accumulatedOffset.height = totalOffsetY * 0.9
                    }
                } else {
                    // Apply boundary constraints only for content larger than viewport
                    if totalOffsetY > maxOffsetY {
                        print("[\(axes)] Vertical: exceeds top boundary, resetting to \(maxOffsetY)")
                        accumulatedOffset.height = maxOffsetY
                    } else if totalOffsetY < minOffsetY {
                        print("[\(axes)] Vertical: exceeds bottom boundary, resetting to \(minOffsetY)")
                        accumulatedOffset.height = minOffsetY
                    } else {
                        print("[\(axes)] Vertical: within boundaries, keeping offset \(accumulatedOffset.height)")
                    }
                }
            } else {
                if accumulatedOffset.height != 0 {
                    print("[\(axes)] Vertical scrolling not allowed, resetting offset to 0")
                    accumulatedOffset.height = 0
                }
            }
        }
        
        print("[\(axes)] Final accumulatedOffset after boundary handling: \(accumulatedOffset)")
        print("[\(axes)] --- Boundary Handling Complete ---\n")
    }
    
    // Start inertia animation
    private func startInertiaAnimation() {
        guard !isAnimating else { return }
        isAnimating = true
        
        print("\n[\(axes)] === Start Inertia Animation ===")
        print("[\(axes)] Initial state:")
        print("[\(axes)] velocity = \(velocity)")
        print("[\(axes)] accumulatedOffset = \(accumulatedOffset)")
        print("[\(axes)] contentSize = \(contentSize)")
        print("[\(axes)] viewportSize = \(viewportSize)")
        
        // Only allow scrolling in the specified axes direction
        let shouldAllowHorizontalScroll = axes.contains(.horizontal)
        let shouldAllowVerticalScroll = axes.contains(.vertical)
        
        // Zero out velocity for non-allowed directions
        if !shouldAllowHorizontalScroll {
            velocity.width = 0
        }
        if !shouldAllowVerticalScroll {
            velocity.height = 0
        }
        
        // Ensure we have valid content dimensions before inertia
        if (contentSize.width <= 0 && shouldAllowHorizontalScroll) ||
           (contentSize.height <= 0 && shouldAllowVerticalScroll) {
            print("[\(axes)] Content size invalid before inertia, forcing measurement")
            forceMeasureContentSize()
            print("[\(axes)] Updated content size: \(contentSize)")
        }
        
        // Calculate inertia offset
        let inertiaOffset = CGSize(
            width: shouldAllowHorizontalScroll ? velocity.width * 0.3 : 0,
            height: shouldAllowVerticalScroll ? velocity.height * 0.3 : 0
        )
        
        // Calculate new offset
        let newOffsetWidth = accumulatedOffset.width + dragOffset.width + inertiaOffset.width
        let newOffsetHeight = accumulatedOffset.height + dragOffset.height + inertiaOffset.height
        
        print("[\(axes)] Calculated inertia: offset=\(inertiaOffset), newOffset=(\(newOffsetWidth), \(newOffsetHeight))")
        
        withAnimation(.bouncy) {
            accumulatedOffset.width = newOffsetWidth
            accumulatedOffset.height = newOffsetHeight
            dragOffset = .zero
            
            // Handle boundary bounce
            handleBounceBackIfNeeded()
        } completion: {
            velocity = .zero
            isAnimating = false
            print("[\(axes)] === Inertia Animation Complete ===\n")
        }
    }

    private func updateContentSize(with size: CGSize, from source: String) {
        print("\n=== Update Content Size ===")
        print("[\(axes)] Source: \(source)")
        print("[\(axes)] UUID: \(id)")
        print("[\(axes)] Current size: \(contentSize)")
        print("[\(axes)] New size: \(size)")
        print("[\(axes)] Last valid sizes - H: \(lastValidHorizontalWidth), V: \(lastValidVerticalHeight)")
        
        // Handle horizontal size updates
        if axes.contains(.horizontal) && !axes.contains(.vertical) {
            if size.width > 0 {
                let expectedWidth = (defaultCardWidth * defaultCardCount) +
                                  (defaultCardSpacing * (defaultCardCount - 1)) +
                                  defaultHorizontalPadding
                
                // Keep the largest width we've seen
                let newWidth = max(lastValidHorizontalWidth, max(size.width, expectedWidth))
                if newWidth != contentSize.width {
                    print("[\(axes)] Updating horizontal width:")
                    print("  - Current width: \(contentSize.width)")
                    print("  - New width: \(newWidth)")
                    print("  - Expected width: \(expectedWidth)")
                    print("  - Measured width: \(size.width)")
                    print("  - Last valid width: \(lastValidHorizontalWidth)")
                    contentSize.width = newWidth
                    lastValidHorizontalWidth = newWidth
                }
            } else {
                print("[\(axes)] Invalid horizontal width: \(size.width), keeping current width: \(contentSize.width)")
            }
        }
        
        // Handle vertical size updates
        if axes.contains(.vertical) && !axes.contains(.horizontal) {
            if size.height > 0 {
                let expectedHeight = (defaultItemHeight * defaultItemCount) +
                                   (defaultItemSpacing * (defaultItemCount - 1)) +
                                   defaultVerticalPadding
                
                // Keep the larger of measured and expected height
                let newHeight = max(size.height, expectedHeight)
                if newHeight != contentSize.height {
                    print("[\(axes)] Updating vertical height:")
                    print("  - Current height: \(contentSize.height)")
                    print("  - New height: \(newHeight)")
                    print("  - Expected height: \(expectedHeight)")
                    print("  - Measured height: \(size.height)")
                    print("  - Last valid height: \(lastValidVerticalHeight)")
                    contentSize.height = newHeight
                    lastValidVerticalHeight = newHeight
                }
            } else {
                print("[\(axes)] Invalid vertical height: \(size.height), keeping current height: \(contentSize.height)")
            }
        }
        
        print("[\(axes)] Final size: \(contentSize)")
        print("=== Update Content Size End ===\n")
    }

    /// Updates the velocity based on drag translation
    private func updateVelocity(translation: CGPoint) {
        let timeDelta = Date().timeIntervalSince(lastUpdateTime)
        guard timeDelta > 0 else { return }
        
        let shouldAllowHorizontalScroll = axes.contains(.horizontal)
        let shouldAllowVerticalScroll = axes.contains(.vertical)
        
        let deltaX = shouldAllowHorizontalScroll ? translation.x - lastDragPosition.width : 0
        let deltaY = shouldAllowVerticalScroll ? translation.y - lastDragPosition.height : 0
        
        let maxVelocityChange: CGFloat = 1000
        
        if shouldAllowHorizontalScroll {
            let rawVelocityX = (deltaX / CGFloat(timeDelta)) * speedFactor
            let clampedDeltaVelocityX = max(min(rawVelocityX - velocity.width, maxVelocityChange), -maxVelocityChange)
            velocity.width = velocity.width * 0.7 + clampedDeltaVelocityX * 0.3
            velocity.width = max(min(velocity.width, 2000), -2000)
        } else {
            velocity.width = 0
        }
        
        if shouldAllowVerticalScroll {
            let rawVelocityY = (deltaY / CGFloat(timeDelta)) * speedFactor
            let clampedDeltaVelocityY = max(min(rawVelocityY - velocity.height, maxVelocityChange), -maxVelocityChange)
            velocity.height = velocity.height * 0.7 + clampedDeltaVelocityY * 0.3
            velocity.height = max(min(velocity.height, 2000), -2000)
        } else {
            velocity.height = 0
        }
    }
    
    /// Forces content size measurement when automatic measurement fails
    private func forceMeasureContentSize() {
        if axes.contains(.horizontal) {
            let estimatedContentWidth = (defaultCardWidth * defaultCardCount) + 
                                      (defaultCardSpacing * (defaultCardCount - 1)) + 
                                      defaultHorizontalPadding
            
            if estimatedContentWidth > contentSize.width {
                contentSize.width = estimatedContentWidth
                lastValidHorizontalWidth = estimatedContentWidth
            }
        }
        
        if axes.contains(.vertical) {
            let estimatedContentHeight = (defaultItemHeight * defaultItemCount) + 
                                       (defaultItemSpacing * (defaultItemCount - 1)) + 
                                       defaultVerticalPadding
            
            if estimatedContentHeight > contentSize.height {
                contentSize.height = estimatedContentHeight
                lastValidVerticalHeight = estimatedContentHeight
            }
        }
    }
    
    /// Calculates the scroll offset with bounce effect
    private func calculateOffset(for axis: Axis, in geometry: GeometryProxy) -> CGFloat {
        // Check if scrolling is allowed for this axis
        switch axis {
        case .horizontal where !axes.contains(.horizontal),
             .vertical where !axes.contains(.vertical):
            return 0
        default:
            break
        }
        
        let currentOffset: CGFloat
        let contentLength: CGFloat
        let viewportLength: CGFloat
        
        switch axis {
        case .horizontal:
            currentOffset = accumulatedOffset.width + dragOffset.width
            contentLength = contentSize.width
            viewportLength = geometry.size.width
        case .vertical:
            currentOffset = accumulatedOffset.height + dragOffset.height
            contentLength = contentSize.height
            viewportLength = geometry.size.height
        }
        
        // Handle invalid dimensions
        if contentLength <= 0 || viewportLength <= 0 {
            return currentOffset * 0.8 // Soft bounce for invalid dimensions
        }
        
        // Determine content size relative to viewport
        let margin: CGFloat = axis == .horizontal ? 20.0 : 20.0
        let isContentSmallerThanViewport = contentLength > 0 && contentLength < (viewportLength - margin)
        
        // Apply elastic effect for small content
        if isContentSmallerThanViewport {
            return currentOffset * 0.6
        }
        
        // Calculate boundaries
        let maxOffset: CGFloat = 0.0
        let minOffset: CGFloat
        
        switch axis {
        case .horizontal:
            let effectiveContentLength = contentLength < viewportLength ? viewportLength - margin : contentLength
            minOffset = viewportLength - effectiveContentLength
        case .vertical:
            minOffset = viewportLength - contentLength
        }
        
        // Apply bounce effect when exceeding boundaries
        if currentOffset > maxOffset {
            let overscroll = currentOffset - maxOffset
            return maxOffset + (overscroll * bounceCoefficient)
        } else if currentOffset < minOffset {
            let overscroll = minOffset - currentOffset
            return minOffset - (overscroll * bounceCoefficient)
        }
        
        return currentOffset
    }
    
    /// Handles bounce back animation when content is dragged beyond boundaries
    private func handleBounceBackIfNeeded() {
        let totalOffsetX = accumulatedOffset.width + dragOffset.width
        let totalOffsetY = accumulatedOffset.height + dragOffset.height
        
        // Ensure valid content size
        if (contentSize.width <= 0 && axes.contains(.horizontal)) ||
           (contentSize.height <= 0 && axes.contains(.vertical)) {
            forceMeasureContentSize()
        }
        
        guard contentSize.width > 0, contentSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0 else {
            return
        }
        
        let horizontalScrollingMargin: CGFloat = 20.0
        let verticalScrollingMargin: CGFloat = 20.0
        
        let contentSmallerThanViewportHorizontally = contentSize.width > 0 && 
            contentSize.width < (viewportSize.width - horizontalScrollingMargin)
        let contentSmallerThanViewportVertically = contentSize.height > 0 && 
            contentSize.height < (viewportSize.height - verticalScrollingMargin)
        
        withAnimation(.bouncy) {
            handleHorizontalBounce(totalOffsetX: totalOffsetX,
                                 contentSmallerThanViewport: contentSmallerThanViewportHorizontally)
            handleVerticalBounce(totalOffsetY: totalOffsetY,
                               contentSmallerThanViewport: contentSmallerThanViewportVertically)
        }
    }
    
    /// Handles horizontal bounce animation
    private func handleHorizontalBounce(totalOffsetX: CGFloat, contentSmallerThanViewport: Bool) {
        guard axes.contains(.horizontal) else {
            if accumulatedOffset.width != 0 {
                accumulatedOffset.width = 0
            }
            return
        }
        
        if contentSmallerThanViewport {
            // Apply progressive damping based on offset magnitude
            if abs(totalOffsetX) > 100 {
                accumulatedOffset.width = totalOffsetX * 0.5
                if abs(accumulatedOffset.width) < 1.0 {
                    accumulatedOffset.width = 0
                }
            } else if abs(totalOffsetX) > 50 {
                accumulatedOffset.width = totalOffsetX * 0.7
            } else {
                accumulatedOffset.width = totalOffsetX * 0.9
            }
        } else {
            // Apply boundary constraints
            let maxOffsetX = 0.0
            let effectiveContentWidth = contentSize.width < viewportSize.width ?
                viewportSize.width - 20.0 : contentSize.width
            let minOffsetX = viewportSize.width - effectiveContentWidth
            
            if totalOffsetX > maxOffsetX {
                accumulatedOffset.width = maxOffsetX
            } else if totalOffsetX < minOffsetX {
                accumulatedOffset.width = minOffsetX
            }
        }
    }
    
    /// Handles vertical bounce animation
    private func handleVerticalBounce(totalOffsetY: CGFloat, contentSmallerThanViewport: Bool) {
        guard axes.contains(.vertical) else {
            if accumulatedOffset.height != 0 {
                accumulatedOffset.height = 0
            }
            return
        }
        
        if contentSmallerThanViewport {
            // Apply progressive damping based on offset magnitude
            if abs(totalOffsetY) > 100 {
                accumulatedOffset.height = totalOffsetY * 0.5
                if abs(accumulatedOffset.height) < 1.0 {
                    accumulatedOffset.height = 0
                }
            } else if abs(totalOffsetY) > 50 {
                accumulatedOffset.height = totalOffsetY * 0.7
            } else {
                accumulatedOffset.height = totalOffsetY * 0.9
            }
        } else {
            // Apply boundary constraints
            let maxOffsetY = 0.0
            let minOffsetY = viewportSize.height - contentSize.height
            
            if totalOffsetY > maxOffsetY {
                accumulatedOffset.height = maxOffsetY
            } else if totalOffsetY < minOffsetY {
                accumulatedOffset.height = minOffsetY
            }
        }
    }
    
    /// Starts the inertia animation after a drag gesture ends
    private func startInertiaAnimation() {
        guard !isAnimating else { return }
        isAnimating = true
        
        // Only allow scrolling in enabled directions
        if !axes.contains(.horizontal) {
            velocity.width = 0
        }
        if !axes.contains(.vertical) {
            velocity.height = 0
        }
        
        // Ensure valid content size
        if (contentSize.width <= 0 && axes.contains(.horizontal)) ||
           (contentSize.height <= 0 && axes.contains(.vertical)) {
            forceMeasureContentSize()
        }
        
        // Calculate inertia offset
        let inertiaOffset = CGSize(
            width: axes.contains(.horizontal) ? velocity.width * 0.3 : 0,
            height: axes.contains(.vertical) ? velocity.height * 0.3 : 0
        )
        
        let newOffset = CGSize(
            width: accumulatedOffset.width + dragOffset.width + inertiaOffset.width,
            height: accumulatedOffset.height + dragOffset.height + inertiaOffset.height
        )
        
        withAnimation(.bouncy) {
            accumulatedOffset = newOffset
            dragOffset = .zero
            handleBounceBackIfNeeded()
        } completion: {
            velocity = .zero
            isAnimating = false
        }
    }
} 