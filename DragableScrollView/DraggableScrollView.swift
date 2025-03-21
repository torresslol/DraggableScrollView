import SwiftUI

/// A ScrollView that can be dragged with a mouse
/// Enables users to scroll content using mouse drag, similar to touch scrolling
/// Supports inertial scrolling for natural, fluid motion
public struct DraggableScrollView<Content: View>: View {
    // MARK: - Properties
    
    /// Scroll direction
    public var axes: Axis.Set
    
    /// Whether to show scroll indicators
    public var showsIndicators: Bool
    
    /// Scroll speed factor, higher value means faster scrolling
    public var speedFactor: CGFloat
    
    /// Inertia decrease factor (0-1), lower value stops inertia faster
    public var momentumDecreaseFactor: CGFloat
    
    /// Minimum velocity threshold to stop inertial scrolling
    public var minimumVelocity: CGFloat
    
    /// Whether to enable inertial scrolling
    public var inertiaEnabled: Bool
    
    /// Content view builder
    private var content: () -> Content
    
    @State private var dragOffset: CGSize = .zero
    @State private var lastDragPosition: CGSize = .zero
    @State private var lastUpdateTime: Date = Date()
    @State private var velocity: CGSize = .zero
    @State private var isAnimating = false
    @State private var accumulatedOffset: CGSize = .zero
    @State private var contentSize: CGSize = .zero
    @State private var viewportSize: CGSize = .zero
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
    
    // MARK: - Initialization
    
    /// Create a mouse-draggable ScrollView
    /// - Parameters:
    ///   - axes: Scroll direction, defaults to vertical
    ///   - showsIndicators: Whether to show scroll indicators, defaults to true
    ///   - speedFactor: Scroll speed factor, defaults to 1.2
    ///   - momentumDecreaseFactor: Inertia decrease factor, defaults to 0.95
    ///   - minimumVelocity: Minimum velocity threshold to stop inertial scrolling, defaults to 3.0
    ///   - inertiaEnabled: Whether to enable inertial scrolling, defaults to true
    ///   - content: Content view builder
    public init(
        axes: Axis.Set = [.vertical],
        showsIndicators: Bool = true,
        speedFactor: CGFloat = 1.2,
        momentumDecreaseFactor: CGFloat = 0.95,
        minimumVelocity: CGFloat = 3.0,
        inertiaEnabled: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.speedFactor = speedFactor
        self.momentumDecreaseFactor = momentumDecreaseFactor
        self.minimumVelocity = minimumVelocity
        self.inertiaEnabled = inertiaEnabled
        self.content = content
    }
    
    // MARK: - Body
    
    public var body: some View {
        GeometryReader { geometry in
            ScrollView(axes, showsIndicators: showsIndicators) {
                ZStack(alignment: .topLeading) {
                    // Invisible frame to establish minimum content size
                    // This ensures we always have a valid content size even before the real content is measured
                    Rectangle()
                        .frame(
                            width: axes.contains(.horizontal) ? max(1000, geometry.size.width * 1.5) : nil,
                            height: axes.contains(.vertical) ? max(1000, geometry.size.height * 1.5) : nil
                        )
                        .opacity(0)
                    
                    // Actual content
                    content()
                        .modifier(ContentSizeModifier())
                        .background(
                            GeometryReader { contentGeometry in
                                Color.clear
                                    .preference(key: ContentSizePreferenceKey.self, value: contentGeometry.size)
                                    .onAppear {
                                        print("Content appeared with size: \(contentGeometry.size)")
                                        if contentSize.width <= 0 || contentSize.height <= 0 {
                                            contentSize = contentGeometry.size
                                        }
                                    }
                            }
                        )
                }
                .offset(
                    x: calculateOffset(for: .horizontal, in: geometry),
                    y: calculateOffset(for: .vertical, in: geometry)
                )
            }
            .onPreferenceChange(ContentSizePreferenceKey.self) { size in
                print("Content size preference changed: \(size)")
                // Always update with the preference size if it has valid dimensions
                if size.width > 0 && size.height > 0 {
                    print("Updating content size with valid dimensions: \(size)")
                    contentSize = size
                } else if size.width > 0 && axes.contains(.horizontal) {
                    // If only width is valid and we're scrolling horizontally
                    print("Updating content width: \(size.width)")
                    contentSize.width = size.width
                } else if size.height > 0 && axes.contains(.vertical) {
                    // If only height is valid and we're scrolling vertically
                    print("Updating content height: \(size.height)")
                    contentSize.height = size.height
                }
            }
            .onAppear {
                self.viewportSize = geometry.size
                self.geometryInitialized = true
                
                print("View appeared with viewport size: \(geometry.size)")
                
                // Set up alternative content size measurement notification listener
//                NotificationCenter.default.addObserver(
//                    forName: Notification.Name("ContentSizeMeasured"),
//                    object: nil,
//                    queue: .main
//                ) { notification in
//                    if let size = notification.userInfo?["size"] as? CGSize,
//                       size.width > 0 || size.height > 0 {
//                        print("Content size notification received: \(size)")
//                        self.contentSize = size
//                    }
//                }
                
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
                // Remove notification observer and cancel timer
                NotificationCenter.default.removeObserver(self)
            }
            .onChange(of: geometry.size) { newSize in
                self.viewportSize = newSize
                print("Viewport size changed: \(newSize)")
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .local)
                .onChanged { value in
                    let translation = value.translation
                    
                    // Only allow scrolling in the specified axes direction
                    let shouldAllowHorizontalScroll = axes.contains(.horizontal)
                    let shouldAllowVerticalScroll = axes.contains(.vertical)
                    
                    // Set drag offset based on allowed scroll direction
                    let newDragOffset = CGSize(
                        width: shouldAllowHorizontalScroll ? translation.width : 0,
                        height: shouldAllowVerticalScroll ? translation.height : 0
                    )
                    
                    // Only log on significant changes to avoid console spam
                    if abs(dragOffset.width - newDragOffset.width) > 20 || abs(dragOffset.height - newDragOffset.height) > 20 {
                        print("Drag changed: translation=\(translation), axes=\(axes)")
                        print("Content vs viewport: horizontal=\(contentSize.width) vs \(viewportSize.width), vertical=\(contentSize.height) vs \(viewportSize.height)")
                        print("Allow scroll: horizontal=\(shouldAllowHorizontalScroll), vertical=\(shouldAllowVerticalScroll)")
                        
                        // Check content size during significant drag changes
                        if shouldAllowHorizontalScroll && (contentSize.width <= 0 || contentSize.width < viewportSize.width) {
                            // Content size is invalid or smaller than viewport, apply estimation
                            forceMeasureContentSize()
                        }
                        
                        if shouldAllowVerticalScroll && (contentSize.height <= 0 || contentSize.height < viewportSize.height) {
                            forceMeasureContentSize()
                        }
                    }
                    
                    dragOffset = newDragOffset
                    
                    // Calculate velocity
                    let now = Date()
                    let timeDelta = now.timeIntervalSince(lastUpdateTime)
                    
                    if timeDelta > 0 {
                        // Only calculate velocity for allowed directions
                        let deltaX = shouldAllowHorizontalScroll ? translation.width - lastDragPosition.width : 0
                        let deltaY = shouldAllowVerticalScroll ? translation.height - lastDragPosition.height : 0
                        
                        // Limit maximum velocity change
                        let maxVelocityChange: CGFloat = 1000
                        
                        // Smooth velocity calculation for allowed directions
                        if shouldAllowHorizontalScroll {
                            let rawVelocityX = (deltaX / CGFloat(timeDelta)) * speedFactor
                            let clampedDeltaVelocityX = max(min(rawVelocityX - velocity.width, maxVelocityChange), -maxVelocityChange)
                            velocity.width = velocity.width * 0.7 + clampedDeltaVelocityX * 0.3
                            // Limit final velocity
                            velocity.width = max(min(velocity.width, 2000), -2000)
                        } else {
                            // If horizontal scrolling isn't allowed, zero out the velocity
                            velocity.width = 0
                        }
                        
                        if shouldAllowVerticalScroll {
                            let rawVelocityY = (deltaY / CGFloat(timeDelta)) * speedFactor
                            let clampedDeltaVelocityY = max(min(rawVelocityY - velocity.height, maxVelocityChange), -maxVelocityChange)
                            velocity.height = velocity.height * 0.7 + clampedDeltaVelocityY * 0.3
                            // Limit final velocity
                            velocity.height = max(min(velocity.height, 2000), -2000)
                        } else {
                            // If vertical scrolling isn't allowed, zero out the velocity
                            velocity.height = 0
                        }
                    }
                    
                    lastDragPosition = translation
                    lastUpdateTime = now
                }
                .onEnded { value in
                    print("\n=== Drag Ended ===")
                    print("Final velocity = \(velocity)")
                    print("Current accumulatedOffset = \(accumulatedOffset)")
                    print("Final dragOffset = \(dragOffset)")
                    print("contentSize = \(contentSize)")
                    print("viewportSize = \(viewportSize)")
                    
                    // On drag end, always ensure we have valid content size for boundary calculations
                    if (contentSize.width <= 0 && axes.contains(.horizontal)) ||
                       (contentSize.height <= 0 && axes.contains(.vertical)) {
                        print("Content size invalid at drag end, forcing measurement")
                        forceMeasureContentSize()
                        print("Updated content size: \(contentSize)")
                    }
                    
                    // Update accumulated offset
                    accumulatedOffset.width += dragOffset.width
                    accumulatedOffset.height += dragOffset.height
                    
                    print("Updated accumulatedOffset = \(accumulatedOffset)")
                    
                    // Handle boundary bounce
                    handleBounceBackIfNeeded()
                    
                    print("After boundary handleBounceBackIfNeeded: accumulatedOffset = \(accumulatedOffset)")
                    
                    // Reset drag offset
                    dragOffset = .zero
                    lastDragPosition = .zero
                    
                    // Check if velocity is significant enough to start inertial scrolling
                    let hasSignificantHorizontalVelocity = axes.contains(.horizontal) && abs(velocity.width) > minimumVelocity
                    let hasSignificantVerticalVelocity = axes.contains(.vertical) && abs(velocity.height) > minimumVelocity
                    
                    print("Has significant velocity: horizontal=\(hasSignificantHorizontalVelocity), vertical=\(hasSignificantVerticalVelocity)")
                    
                    if inertiaEnabled && (hasSignificantHorizontalVelocity || hasSignificantVerticalVelocity) {
                        startInertiaAnimation()
                    } else {
                        // If velocity is not enough, reset it
                        print("Velocity not significant, resetting")
                        velocity = .zero
                    }
                    
                    print("=== Drag Handling Complete ===\n")
                }
        )
    }
    
    // Try to measure content size using multiple methods
    private func attemptToMeasureContentSize() {
        print("Attempting to measure content size")
        
        // For horizontal scrolling, estimate based on items if measurement fails
        if axes.contains(.horizontal) && contentSize.width <= 0 {
            // Create a reasonable estimate for horizontal content in case measurement fails
            let estimatedContentWidth: CGFloat = max(1000, viewportSize.width * 3)
            print("Using estimated horizontal content width: \(estimatedContentWidth)")
            contentSize.width = estimatedContentWidth
        }
        
        // For vertical scrolling, estimate based on items if measurement fails
        if axes.contains(.vertical) && contentSize.height <= 0 {
            // Create a reasonable estimate for vertical content in case measurement fails
            let estimatedContentHeight: CGFloat = max(1000, viewportSize.height * 3)
            print("Using estimated vertical content height: \(estimatedContentHeight)")
            contentSize.height = estimatedContentHeight
        }
        
        // Trigger layout update to potentially get new size information
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("RequestContentSizeMeasurement"),
                object: nil
            )
        }
    }
    
    // Force content size measurement as a last resort
    private func forceMeasureContentSize() {
        print("Force measuring content size")
        
        // For horizontal scrolling, use a more aggressive estimate
        if axes.contains(.horizontal) && contentSize.width <= 0 {
            // For horizontal scroll with cards, we can make a reasonable estimate
            let estimatedItemWidth: CGFloat = defaultCardWidth
            let estimatedSpacing: CGFloat = defaultCardSpacing
            let estimatedItems: CGFloat = defaultCardCount
            let estimatedPadding: CGFloat = defaultHorizontalPadding
            
            let estimatedContentWidth = (estimatedItemWidth * estimatedItems) + 
                                       (estimatedSpacing * (estimatedItems - 1)) + 
                                       estimatedPadding
                                       
            print("Using forced estimated horizontal content width: \(estimatedContentWidth)")
            contentSize.width = estimatedContentWidth
        }
        
        // For vertical scrolling, use a more aggressive estimate
        if axes.contains(.vertical) && contentSize.height <= 0 {
            // For vertical scrolling, similar approach
            let estimatedItemHeight: CGFloat = defaultItemHeight
            let estimatedSpacing: CGFloat = defaultItemSpacing
            let estimatedItems: CGFloat = defaultItemCount
            let estimatedPadding: CGFloat = defaultVerticalPadding
            
            let estimatedContentHeight = (estimatedItemHeight * estimatedItems) + 
                                        (estimatedSpacing * (estimatedItems - 1)) + 
                                        estimatedPadding
                                        
            print("Using forced estimated vertical content height: \(estimatedContentHeight)")
            contentSize.height = estimatedContentHeight
        }
    }
    
    // Calculate actual offset with bounce effect
    private func calculateOffset(for axis: Axis, in geometry: GeometryProxy) -> CGFloat {
        // Check if scrolling is allowed for this axis
        switch axis {
        case .horizontal:
            if !axes.contains(.horizontal) {
                return 0 // No horizontal scrolling if not enabled
            }
        case .vertical:
            if !axes.contains(.vertical) {
                return 0 // No vertical scrolling if not enabled
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
        
        // If content size is invalid, allow free scrolling but apply bounce effect
        if contentLength <= 0 || viewportLength <= 0 {
            // Use smaller bounce coefficient for freer scrolling
            let softBounceCoefficient: CGFloat = 0.8
            
            // Consider accumulated offset even when dimensions are not ready
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
        case .vertical:
            isContentSmallerThanViewport = contentLength > 0 && 
                contentLength < (viewportLength - verticalScrollingMargin)
        }
        
        // If content is smaller than viewport, apply elastic effect with stronger resistance
        if isContentSmallerThanViewport {
            // For smaller content, allow scrolling but with stronger bounce back effect
            let smallContentBounceCoefficient: CGFloat = 0.6
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
        case .vertical:
            maxOffset = 0.0  // Top boundary
            minOffset = viewportLength - contentLength  // Bottom boundary (negative)
        }
        
        // Apply bounce effect when exceeding boundaries
        if currentOffset > maxOffset {
            let overscroll = currentOffset - maxOffset
            let bounceOffset = maxOffset + (overscroll * bounceCoefficient)
            return bounceOffset
        } else if currentOffset < minOffset {
            let overscroll = minOffset - currentOffset
            let bounceOffset = minOffset - (overscroll * bounceCoefficient)
            return bounceOffset
        }
        
        return currentOffset
    }
    
    // Start inertia animation
    private func startInertiaAnimation() {
        guard !isAnimating else { return }
        isAnimating = true
        
        print("\n=== Start Inertia Animation ===")
        print("Initial state:")
        print("velocity = \(velocity)")
        print("accumulatedOffset = \(accumulatedOffset)")
        print("dragOffset = \(dragOffset)")
        print("contentSize = \(contentSize)")
        print("viewportSize = \(viewportSize)")
        print("axis = \(axes)")
        
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
            print("Content size invalid before inertia, forcing measurement")
            forceMeasureContentSize()
            print("Updated content size: \(contentSize)")
        }
        
        // CRITICAL: For horizontal scrolling, even if content is slightly smaller than viewport,
        // we should still allow full scrolling to show all content
        // We define a margin (e.g., 20 points) where we'll treat content as equal to viewport
        let horizontalScrollingMargin: CGFloat = 20.0
        let verticalScrollingMargin: CGFloat = 20.0
        
        // We consider content smaller only if it's significantly smaller than viewport
        let contentSmallerThanViewportHorizontally = contentSize.width > 0 && 
            contentSize.width < (viewportSize.width - horizontalScrollingMargin)
        let contentSmallerThanViewportVertically = contentSize.height > 0 && 
            contentSize.height < (viewportSize.height - verticalScrollingMargin)
        
        print("Allow scroll: horizontal=\(shouldAllowHorizontalScroll), vertical=\(shouldAllowVerticalScroll)")
        print("Content smaller than viewport (with margin): horizontal=\(contentSmallerThanViewportHorizontally), vertical=\(contentSmallerThanViewportVertically)")
        
        // If velocity is zero for all allowed axes, exit early
        if (!shouldAllowHorizontalScroll || abs(velocity.width) < minimumVelocity) &&
           (!shouldAllowVerticalScroll || abs(velocity.height) < minimumVelocity) {
            print("No significant velocity for allowed axes, exiting early")
            dragOffset = .zero
            velocity = .zero
            isAnimating = false
            return
        }
        
        // Horizontal scrolling inversion detection:
        // For horizontal scrolling in SwiftUI with DragGesture, the coordinate system is:
        // - Dragging left (negative translation): content should move right
        // - Dragging right (positive translation): content should move left
        //
        // Consider adjusting the sign of velocity and accumulated offset for horizontal scrolling
        // to match the expected behavior with standard SwiftUI ScrollView + DragGesture
        if shouldAllowHorizontalScroll {
            // If user is swiping left (negative velocity) to see right content,
            // for proper scrolling we need positive offset
            if velocity.width < 0 && accumulatedOffset.width < 0 {
                // This means user is swiping left, let's keep the offset negative
                // (no change needed, current behavior is correct)
                print("Horizontal direction check: swipe left to see right content, keeping negative offset")
            } else if velocity.width > 0 && accumulatedOffset.width > 0 {
                // This means user is swiping right, let's keep the offset positive
                // (no change needed, current behavior is correct)
                print("Horizontal direction check: swipe right to see left content, keeping positive offset")
            }
        }
        
        // Check if offset direction is correct for vertical (this remains unchanged)
        if shouldAllowVerticalScroll && accumulatedOffset.height > 0 && velocity.height < 0 {
            print("Detected vertical direction mismatch - correcting")
            // Reverse offset direction to match expected coordinate system
            accumulatedOffset.height = -accumulatedOffset.height
            print("Corrected accumOffset = \(accumulatedOffset)")
        }
        
        // Similar correction for horizontal direction
        if shouldAllowHorizontalScroll && accumulatedOffset.width > 0 && velocity.width < 0 {
            print("Detected horizontal direction mismatch - correcting")
            // Reverse offset direction to match expected coordinate system
            accumulatedOffset.width = -accumulatedOffset.width
            print("Corrected accumOffset = \(accumulatedOffset)")
        }
        
        // If dimensions are not ready, use simple inertia
        if contentSize.width <= 0 || contentSize.height <= 0 || viewportSize.width <= 0 || viewportSize.height <= 0 {
            print("\nDimensions not ready, using simple inertia")
            let inertiaOffset = CGSize(
                width: axes.contains(.horizontal) ? velocity.width * 0.3 : 0,
                height: axes.contains(.vertical) ? velocity.height * 0.3 : 0
            )
            
            // Preserve previous accumulated offset
            let newOffsetWidth = accumulatedOffset.width + inertiaOffset.width
            let newOffsetHeight = accumulatedOffset.height + inertiaOffset.height
            
            print("Simple inertia: inertiaOffset = \(inertiaOffset)")
            print("newOffsetWidth = \(newOffsetWidth), newOffsetHeight = \(newOffsetHeight)")
            
            withAnimation(.bouncy) {
                accumulatedOffset.width = newOffsetWidth
                accumulatedOffset.height = newOffsetHeight
                dragOffset = .zero
            } completion: {
                velocity = .zero
                isAnimating = false
            }
            
            print("\nFinal state:")
            print("accumulatedOffset = \(accumulatedOffset)")
            print("=== Inertia Animation End ===\n")
            return
        }
        
        // Maximum bounce distance
        let maxBounceDistance = 30.0
        
        // Limit maximum velocity
        velocity.width = max(min(velocity.width, 2000), -2000)
        velocity.height = max(min(velocity.height, 2000), -2000)
        
        print("\nAfter velocity limit:")
        print("velocity = \(velocity)")
        
        // Check for reverse scrolling
        // Normal cases for horizontal:
        // - Scrolling left (showing right content): offset is negative, velocity is negative
        // - Scrolling right (showing left content): offset is positive, velocity is positive
        // Reverse cases for horizontal:
        // - Reverse from left to right: offset is negative, velocity is positive
        // - Reverse from right to left: offset is positive, velocity is negative
        // For vertical (unchanged):
        // - Scrolling up (showing bottom content): offset is negative, velocity is negative
        // - Scrolling down (showing top content): offset is positive, velocity is positive
        // - Reverse from up to down: offset is negative, velocity is positive
        // - Reverse from down to up: offset is positive, velocity is negative
        
        // For horizontal
        let horizDirectionCheck1 = accumulatedOffset.width < 0 && velocity.width > 0
        let horizDirectionCheck2 = accumulatedOffset.width > 0 && velocity.width < 0
        let isReverseHorizontalScroll = axes.contains(.horizontal) && 
            (horizDirectionCheck1 || horizDirectionCheck2)
        
        // For vertical
        let vertDirectionCheck1 = accumulatedOffset.height < 0 && velocity.height > 0
        let vertDirectionCheck2 = accumulatedOffset.height > 0 && velocity.height < 0
        let isReverseVerticalScroll = axes.contains(.vertical) && 
            (vertDirectionCheck1 || vertDirectionCheck2)
            
        print("\nReverse scroll check:")
        if axes.contains(.horizontal) {
            print("Horizontal checks: ")
            print("  Check1 (offset<0 && vel>0): \(horizDirectionCheck1) (offset=\(accumulatedOffset.width), vel=\(velocity.width))")
            print("  Check2 (offset>0 && vel<0): \(horizDirectionCheck2) (offset=\(accumulatedOffset.width), vel=\(velocity.width))")
            print("  isReverseHorizontalScroll = \(isReverseHorizontalScroll)")
        }
        
        if axes.contains(.vertical) {
            print("Vertical checks: ")
            print("  Check1 (offset<0 && vel>0): \(vertDirectionCheck1) (offset=\(accumulatedOffset.height), vel=\(velocity.height))")
            print("  Check2 (offset>0 && vel<0): \(vertDirectionCheck2) (offset=\(accumulatedOffset.height), vel=\(velocity.height))")
            print("  isReverseVerticalScroll = \(isReverseVerticalScroll)")
        }
        
        // If reverse scrolling, go back to nearest boundary
        if isReverseVerticalScroll || isReverseHorizontalScroll {
            print("\nExecuting reverse scroll handling")
            withAnimation(.bouncy) {
                if isReverseVerticalScroll {
                    // For vertical, we reset to 0 since going to opposite edge would be disorienting
                    print("Resetting vertical offset to 0")
                    accumulatedOffset.height = 0
                }
                if isReverseHorizontalScroll {
                    // For horizontal, we reset to left edge as default when direction changes
                    print("Horizontal direction change detected, resetting to left edge")
                    accumulatedOffset.width = 0
                }
            }
            dragOffset = .zero
            velocity = .zero
            isAnimating = false
            return
        }
        
        // Normal inertia scrolling
        let inertiaOffset = CGSize(
            width: axes.contains(.horizontal) ? velocity.width * 0.3 : 0,
            height: axes.contains(.vertical) ? velocity.height * 0.3 : 0
        )
        
        // Calculate new offset
        let newOffsetWidth = accumulatedOffset.width + dragOffset.width + inertiaOffset.width
        let newOffsetHeight = accumulatedOffset.height + dragOffset.height + inertiaOffset.height
        
        // Calculate content boundaries
        // For horizontal scrolling:
        // - maxOffsetX (0.0): Content is at left edge
        // - minOffsetX (negative): Content is at right edge (viewportSize.width - contentSize.width)
        let maxOffsetX = 0.0 // Left edge boundary
        
        // If content width is close to viewport width, treat it as equal or larger
        // to allow full scrolling of all content
        let effectiveContentWidth = contentSmallerThanViewportHorizontally ? 
            viewportSize.width - horizontalScrollingMargin : contentSize.width
        
        let minOffsetX = viewportSize.width - effectiveContentWidth // Right edge boundary
        print("viewportSize.width = \(viewportSize.width) effectiveContentWidth = \(effectiveContentWidth)")
        // For vertical scrolling:
        let maxOffsetY = 0.0 // Top edge boundary
        let minOffsetY = viewportSize.height - contentSize.height
        
        print("\nBoundary calculation:")
        print("maxOffsetX = \(maxOffsetX)")
        print("minOffsetX = \(minOffsetX)")
        print("minOffsetY = \(minOffsetY)")
        print("newOffsetWidth = \(newOffsetWidth)")
        print("newOffsetHeight = \(newOffsetHeight)")
        
        // Check if out of bounds
        // For content larger than viewport, we check against actual boundaries
        // For content smaller than viewport, we use a more generous boundary check
        let isOutOfBoundsX: Bool
        let isOutOfBoundsY: Bool
        
        // For horizontal scrolling:
        // - Out of bounds left: newOffsetWidth > maxOffsetX (0)
        // - Out of bounds right: newOffsetWidth < minOffsetX (negative)
        if contentSmallerThanViewportHorizontally {
            // For smaller content, allow more freedom but still have boundaries
            isOutOfBoundsX = abs(newOffsetWidth) > 100 // Use a larger threshold for small content
        } else {
            // Normal boundary check for larger content
            isOutOfBoundsX = newOffsetWidth > maxOffsetX || newOffsetWidth < minOffsetX
        }
        
        if contentSmallerThanViewportVertically {
            // For smaller content, allow more freedom but still have boundaries
            isOutOfBoundsY = abs(newOffsetHeight) > 100 // Use a larger threshold for small content
        } else {
            // Normal boundary check for larger content
            isOutOfBoundsY = newOffsetHeight > maxOffsetY || newOffsetHeight < minOffsetY
        }
        
        print("\nBoundary check:")
        print("isOutOfBoundsX = \(isOutOfBoundsX)")
        print("isOutOfBoundsY = \(isOutOfBoundsY)")
        
        withAnimation(.bouncy) {
            // For horizontal direction
            if axes.contains(.horizontal) {
                if contentSmallerThanViewportHorizontally {
                    // Content is smaller than viewport - allow flexibility with gradual bounce back
                    if isOutOfBoundsX {
                        print("Horizontal out of bounds (small content), applying damping")
                        // Apply stronger damping when far from center
                        accumulatedOffset.width = newOffsetWidth * 0.5
                    } else {
                        print("Horizontal in bounds (small content), applying normal damping")
                        // Apply lighter damping when near center
                        accumulatedOffset.width = newOffsetWidth * 0.8
                    }
                } else {
                    // Content is larger than viewport - apply boundary constraints
                    // In horizontal scrolling:
                    // - If newOffsetWidth > maxOffsetX (0): Content has moved past left edge
                    // - If newOffsetWidth < minOffsetX (negative): Content has moved past right edge
                    if isOutOfBoundsX {
                        if newOffsetWidth > maxOffsetX {
                            print("Horizontal out of bounds (left edge), resetting to \(maxOffsetX)")
                            accumulatedOffset.width = maxOffsetX
                        } else {
                            print("Horizontal out of bounds (right edge), resetting to \(minOffsetX)")
                            accumulatedOffset.width = minOffsetX
                        }
                    } else {
                        print("Horizontal in bounds, applying new offset")
                        accumulatedOffset.width = newOffsetWidth
                    }
                }
            }
            
            // For vertical direction
            if axes.contains(.vertical) {
                if contentSmallerThanViewportVertically {
                    // Content is smaller than viewport - allow flexibility with gradual bounce back
                    if isOutOfBoundsY {
                        print("Vertical out of bounds (small content), applying damping")
                        // Apply stronger damping when far from center
                        accumulatedOffset.height = newOffsetHeight * 0.5
                    } else {
                        print("Vertical in bounds (small content), applying normal damping")
                        // Apply lighter damping when near center
                        accumulatedOffset.height = newOffsetHeight * 0.8
                    }
                } else {
                    // Content is larger than viewport - apply boundary constraints
                    if isOutOfBoundsY {
                        if newOffsetHeight > maxOffsetY {
                            print("Vertical out of bounds (top edge), resetting to \(maxOffsetY)")
                            accumulatedOffset.height = maxOffsetY
                        } else {
                            print("Vertical out of bounds (bottom edge), resetting to \(minOffsetY)")
                            accumulatedOffset.height = minOffsetY
                        }
                    } else {
                        print("Vertical in bounds, applying new offset")
                        accumulatedOffset.height = newOffsetHeight
                    }
                }
            }
            
            dragOffset = .zero
        } completion: {
            velocity = .zero
            isAnimating = false
        }
        
        print("\nFinal state:")
        print("accumulatedOffset = \(accumulatedOffset)")
        print("=== Inertia Animation End ===\n")
    }
    
    // Handle boundary bounce back
    private func handleBounceBackIfNeeded() {
        let totalOffsetX = accumulatedOffset.width + dragOffset.width
        let totalOffsetY = accumulatedOffset.height + dragOffset.height
        
        print("\n--- Handling Boundary Bounce ---")
        print("totalOffsetX = \(totalOffsetX), totalOffsetY = \(totalOffsetY)")
        print("contentSize = \(contentSize), viewportSize = \(viewportSize)")
        
        // If content size is not valid, force measurement before boundary handling
        if (contentSize.width <= 0 && axes.contains(.horizontal)) ||
           (contentSize.height <= 0 && axes.contains(.vertical)) {
            print("Content size invalid before boundary handling, forcing measurement")
            forceMeasureContentSize()
            print("Updated content size: \(contentSize)")
        }
        
        // If content size is still not ready after forcing measurement, skip boundary bounce handling
        if contentSize.width <= 0 || contentSize.height <= 0 || 
           viewportSize.width <= 0 || viewportSize.height <= 0 {
            print("Content or viewport size not ready, skipping boundary handling")
            return
        }
        
        // For horizontal and vertical scrolling, we should allow scrolling when the axis is enabled
        let shouldAllowHorizontalScroll = axes.contains(.horizontal)
        let shouldAllowVerticalScroll = axes.contains(.vertical)
        
        // CRITICAL: For horizontal scrolling, even if content is slightly smaller than viewport,
        // we should still allow full scrolling to show all content
        // We define a margin (e.g., 20 points) where we'll treat content as equal to viewport
        let horizontalScrollingMargin: CGFloat = 20.0
        let verticalScrollingMargin: CGFloat = 20.0
        
        // We consider content smaller only if it's significantly smaller than viewport
        let contentSmallerThanViewportHorizontally = contentSize.width > 0 && 
            contentSize.width < (viewportSize.width - horizontalScrollingMargin)
        let contentSmallerThanViewportVertically = contentSize.height > 0 && 
            contentSize.height < (viewportSize.height - verticalScrollingMargin)
        
        print("Allow scroll: horizontal=\(shouldAllowHorizontalScroll), vertical=\(shouldAllowVerticalScroll)")
        print("Content smaller than viewport (with margin): horizontal=\(contentSmallerThanViewportHorizontally), vertical=\(contentSmallerThanViewportVertically)")
        
        // Calculate content boundaries for horizontal scrolling
        // In horizontal scrolling:
        // - maxOffsetX (0.0): Content is at left edge
        // - minOffsetX (negative): Content is at right edge
        // For content wider than viewport (normal case), boundaries are:
        //   left edge: 0.0
        //   right edge: viewportSize.width - contentSize.width (negative value)
        let maxOffsetX = 0.0  // Left edge boundary
        
        // If content width is close to viewport width, treat it as equal or larger
        // to allow full scrolling of all content
        let effectiveContentWidth = contentSmallerThanViewportHorizontally ? 
            viewportSize.width - horizontalScrollingMargin : contentSize.width
        
        let minOffsetX = viewportSize.width - effectiveContentWidth  // Right boundary (negative)
        
        print("Boundaries: viewportSize = \(viewportSize.width), effectiveContentWidth = \(effectiveContentWidth)")
        
        // For vertical scrolling (remains unchanged)
        let maxOffsetY = 0.0  // Top boundary
        let minOffsetY = viewportSize.height - contentSize.height  // Bottom boundary (negative)
        
        print("Boundaries: maxOffsetX = \(maxOffsetX)")
        print("  minOffsetX = \(minOffsetX), minOffsetY = \(minOffsetY)")
        
        withAnimation(.bouncy) {
            // Handle horizontal direction
            if axes.contains(.horizontal) {
                // For horizontal scrolling, we need to adjust our understanding of boundaries
                if contentSmallerThanViewportHorizontally {
                    // Content is smaller than viewport - allow offset but apply damping for bounce-back
                    if abs(totalOffsetX) > 100 {
                        // If offset is very large, reset to center more aggressively
                        print("Horizontal: content smaller than viewport, large offset, strong damping")
                        accumulatedOffset.width = totalOffsetX * 0.5
                        // If nearly at zero, just set to zero
                        if abs(accumulatedOffset.width) < 1.0 {
                            accumulatedOffset.width = 0
                        }
                    } else if abs(totalOffsetX) > 50 {
                        // Medium offset, medium damping
                        print("Horizontal: content smaller than viewport, medium offset, medium damping")
                        accumulatedOffset.width = totalOffsetX * 0.7
                    } else {
                        // Small offset, light damping
                        print("Horizontal: content smaller than viewport, small offset, light damping")
                        accumulatedOffset.width = totalOffsetX * 0.9
                    }
                } else {
                    // Apply boundary constraints for content larger than viewport
                    // In horizontal scrolling:
                    // - If totalOffsetX > maxOffsetX (0): Content has moved past left edge
                    // - If totalOffsetX < minOffsetX (negative): Content has moved past right edge
                    if totalOffsetX > maxOffsetX {
                        print("Horizontal: exceeds left edge, resetting to \(maxOffsetX)")
                        accumulatedOffset.width = maxOffsetX
                    } else if totalOffsetX < minOffsetX {
                        print("Horizontal: exceeds right edge, resetting to \(minOffsetX)")
                        accumulatedOffset.width = minOffsetX
                    } else {
                        print("Horizontal: within boundaries, keeping offset \(accumulatedOffset.width)")
                    }
                }
            } else {
                // If horizontal scrolling is not allowed, reset any horizontal offset
                if accumulatedOffset.width != 0 {
                    print("Horizontal scrolling not allowed, resetting offset to 0")
                    accumulatedOffset.width = 0
                }
            }
            
            // Handle vertical direction
            if axes.contains(.vertical) {
                if contentSmallerThanViewportVertically {
                    // Content is smaller than viewport - allow offset but apply damping for bounce-back
                    if abs(totalOffsetY) > 100 {
                        // If offset is very large, reset to center more aggressively
                        print("Vertical: content smaller than viewport, large offset, strong damping")
                        accumulatedOffset.height = totalOffsetY * 0.5
                        // If nearly at zero, just set to zero
                        if abs(accumulatedOffset.height) < 1.0 {
                            accumulatedOffset.height = 0
                        }
                    } else if abs(totalOffsetY) > 50 {
                        // Medium offset, medium damping
                        print("Vertical: content smaller than viewport, medium offset, medium damping")
                        accumulatedOffset.height = totalOffsetY * 0.7
                    } else {
                        // Small offset, light damping
                        print("Vertical: content smaller than viewport, small offset, light damping")
                        accumulatedOffset.height = totalOffsetY * 0.9
                    }
                } else {
                    // Apply boundary constraints only for content larger than viewport
                    if totalOffsetY > maxOffsetY {
                        print("Vertical: exceeds top boundary, resetting to \(maxOffsetY)")
                        accumulatedOffset.height = maxOffsetY
                    } else if totalOffsetY < minOffsetY {
                        print("Vertical: exceeds bottom boundary, resetting to \(minOffsetY)")
                        accumulatedOffset.height = minOffsetY
                    } else {
                        print("Vertical: within boundaries, keeping offset \(accumulatedOffset.height)")
                    }
                }
            } else {
                // If vertical scrolling is not allowed, reset any vertical offset
                if accumulatedOffset.height != 0 {
                    print("Vertical scrolling not allowed, resetting offset to 0")
                    accumulatedOffset.height = 0
                }
            }
        }
        
        print("Final accumulatedOffset after boundary handling: \(accumulatedOffset)")
        print("--- Boundary Handling Complete ---\n")
    }
}

// MARK: - Helper Types

private struct ContentSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct ContentSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { contentGeometry in
                    Color.clear
                        .preference(key: ContentSizePreferenceKey.self, value: contentGeometry.size)
                        .onAppear {
                            // Immediately report content size - critical for correct scrolling
                            let size = contentGeometry.size
                            print("Content size immediately detected on appear: \(size)")
                            
                            // Post notification with size information
                            NotificationCenter.default.post(
                                name: Notification.Name("ContentSizeMeasured"),
                                object: nil,
                                userInfo: ["size": size]
                            )
                            
                            // Also post delayed for layout completion
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                NotificationCenter.default.post(
                                    name: Notification.Name("ContentSizeMeasured"),
                                    object: nil,
                                    userInfo: ["size": contentGeometry.size]
                                )
                            }
                        }
                }
            )
            .measureSize { size in
                if size.width > 0 || size.height > 0 {
                    print("MeasureSize detected: \(size)")
                    NotificationCenter.default.post(
                        name: Notification.Name("ContentSizeMeasured"),
                        object: nil,
                        userInfo: ["size": size]
                    )
                }
            }
    }
}

// Extend View to add size measurement functionality
private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let newValue = nextValue()
        // Only update if the new value has positive dimensions
        if newValue.width > 0 || newValue.height > 0 {
            value = newValue
        }
    }
}

private extension View {
    func measureSize(perform action: @escaping (CGSize) -> Void) -> some View {
        self.background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometry.size)
                    .onPreferenceChange(SizePreferenceKey.self) { size in
                        if size.width > 0 || size.height > 0 {
                            action(size)
                        }
                    }
            }
        )
    }
}
