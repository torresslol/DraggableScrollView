import SwiftUI

/// A demonstration view showcasing the capabilities of DraggableScrollView
struct DraggableScrollViewDemo: View {
    // MARK: - Constants
    
    enum Constants {
        static let verticalItemCount = 30
        static let horizontalItemCount = 20
        static let itemSpacing: CGFloat = 20
        static let cornerRadius: CGFloat = 10
        static let containerCornerRadius: CGFloat = 15
        static let verticalContainerHeight: CGFloat = 300
        static let horizontalContainerHeight: CGFloat = 200
        static let cardSize: CGFloat = 150
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack {
            verticalScrollingDemo
            horizontalScrollingDemo
        }
        .padding()
    }
    
    // MARK: - Private Views
    
    /// Demonstrates vertical scrolling capabilities
    private var verticalScrollingDemo: some View {
        VStack {
            titleText("Vertical Scrolling Test")
            
            DraggableScrollView(axes: .vertical) {
                VStack(spacing: Constants.itemSpacing) {
                    ForEach(0..<Constants.verticalItemCount, id: \.self) { index in
                        createVerticalItem(index: index)
                    }
                }
                .padding()
            }
            .frame(height: Constants.verticalContainerHeight)
            .containerStyle()
        }
    }
    
    /// Demonstrates horizontal scrolling capabilities
    private var horizontalScrollingDemo: some View {
        VStack {
            titleText("Horizontal Scrolling Test")
            
            DraggableScrollView(axes: .horizontal, showsIndicators: false) {
                HStack(spacing: Constants.itemSpacing) {
                    ForEach(0..<Constants.horizontalItemCount, id: \.self) { index in
                        createHorizontalCard(index: index)
                    }
                }
                .padding()
            }
            .frame(height: Constants.horizontalContainerHeight)
            .containerStyle()
        }
    }
    
    /// Creates a title text view
    private func titleText(_ text: String) -> some View {
        Text(text)
            .font(.title)
            .padding()
    }
    
    /// Creates a vertical scrolling item
    private func createVerticalItem(index: Int) -> some View {
        RoundedRectangle(cornerRadius: Constants.cornerRadius)
            .fill(Color.blue.opacity(0.1))
            .frame(height: 100)
            .overlay(
                Text("Item \(index + 1)")
                    .foregroundColor(.blue)
            )
    }
    
    /// Creates a horizontal scrolling card
    private func createHorizontalCard(index: Int) -> some View {
        RoundedRectangle(cornerRadius: Constants.cornerRadius)
            .fill(Color.green.opacity(0.1))
            .frame(width: Constants.cardSize, height: Constants.cardSize)
            .overlay(
                Text("Card \(index + 1)")
                    .foregroundColor(.green)
            )
    }
}

// MARK: - View Modifiers

private extension View {
    /// Applies common container styling
    func containerStyle() -> some View {
        self.background(Color.gray.opacity(0.1))
            .cornerRadius(DraggableScrollViewDemo.Constants.containerCornerRadius)
    }
}

#Preview {
    DraggableScrollViewDemo()
} 
