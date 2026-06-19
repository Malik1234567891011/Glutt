import SwiftUI

/// A simple left-to-right wrapping layout. Places subviews in a row until the next one
/// would overflow the proposed width, then wraps to a new line.
struct FlowLayout: Layout {
    var hSpacing: CGFloat = 8
    var vSpacing: CGFloat = 8

    /// Note: wrapping requires a finite proposed width. Given an unbounded width
    /// (nil proposal) every subview is laid out on a single row. A single subview wider
    /// than the container is clamped to the container width so it never overflows.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let w = min(size.width, maxWidth)
            if x > 0, x + w > maxWidth {
                x = 0
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            x += w + hSpacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - hSpacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let w = min(size.width, bounds.width)
            if x > bounds.minX, x + w > bounds.maxX {
                x = bounds.minX
                y += rowHeight + vSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: w, height: size.height))
            x += w + hSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
