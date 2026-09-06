//
//  NotchShape.swift
//  boringNotch
//
// Created by Kai Azim on 2023-08-24.
// Original source: https://github.com/MrKai77/DynamicNotchKit
// Modified by Alexander on 2025-05-18.

import AppKit
import QuartzCore
import SwiftUI

struct NotchShape: Shape {
    private var topCornerRadius: CGFloat
    private var bottomCornerRadius: CGFloat

    init(
        topCornerRadius: CGFloat? = nil,
        bottomCornerRadius: CGFloat? = nil
    ) {
        self.topCornerRadius = topCornerRadius ?? 6
        self.bottomCornerRadius = bottomCornerRadius ?? 14
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get {
            .init(
                topCornerRadius,
                bottomCornerRadius
            )
        }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.minY + topCornerRadius
            ),
            control: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.maxY - bottomCornerRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + topCornerRadius + bottomCornerRadius,
                y: rect.maxY
            ),
            control: CGPoint(
                x: rect.minX + topCornerRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - topCornerRadius - bottomCornerRadius,
                y: rect.maxY
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.maxY - bottomCornerRadius
            ),
            control: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.maxY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.minY + topCornerRadius
            )
        )

        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX,
                y: rect.minY
            ),
            control: CGPoint(
                x: rect.maxX - topCornerRadius,
                y: rect.minY
            )
        )

        path.addLine(
            to: CGPoint(
                x: rect.minX,
                y: rect.minY
            )
        )

        return path
    }
}

struct AnimatedNotchSurfaceShape: Shape {
    let progress: CGFloat
    let closedSize: CGSize
    let openSize: CGSize
    let closedTopCornerRadius: CGFloat
    let closedBottomCornerRadius: CGFloat
    let openTopCornerRadius: CGFloat
    let openBottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let width = interpolated(from: closedSize.width, to: openSize.width)
        let height = interpolated(from: closedSize.height, to: openSize.height)
        let surfaceRect = CGRect(
            x: rect.midX - width / 2,
            y: rect.minY,
            width: max(0, width),
            height: max(0, height)
        )

        return NotchShape(
            topCornerRadius: interpolated(
                from: closedTopCornerRadius,
                to: openTopCornerRadius
            ),
            bottomCornerRadius: interpolated(
                from: closedBottomCornerRadius,
                to: openBottomCornerRadius
            )
        )
        .path(in: surfaceRect)
    }

    private func interpolated(from start: CGFloat, to end: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }
}

struct AnimatedNotchSurfaceView: NSViewRepresentable {
    let isOpen: Bool
    let closedSize: CGSize
    let openSize: CGSize
    let closedTopCornerRadius: CGFloat
    let closedBottomCornerRadius: CGFloat
    let openTopCornerRadius: CGFloat
    let openBottomCornerRadius: CGFloat
    let shadowEnabled: Bool

    func makeNSView(context _: Context) -> NotchSurfaceLayerView {
        NotchSurfaceLayerView()
    }

    func updateNSView(_ view: NotchSurfaceLayerView, context _: Context) {
        view.update(
            configuration: NotchSurfaceConfiguration(
                isOpen: isOpen,
                closedSize: closedSize,
                openSize: openSize,
                closedTopCornerRadius: closedTopCornerRadius,
                closedBottomCornerRadius: closedBottomCornerRadius,
                openTopCornerRadius: openTopCornerRadius,
                openBottomCornerRadius: openBottomCornerRadius,
                shadowEnabled: shadowEnabled
            )
        )
    }
}

private struct NotchSurfaceConfiguration: Equatable {
    let isOpen: Bool
    let closedSize: CGSize
    let openSize: CGSize
    let closedTopCornerRadius: CGFloat
    let closedBottomCornerRadius: CGFloat
    let openTopCornerRadius: CGFloat
    let openBottomCornerRadius: CGFloat
    let shadowEnabled: Bool
}

private final class NotchTransitionAnimationDelegate: NSObject, CAAnimationDelegate {
    let onStop: (Bool) -> Void

    init(onStop: @escaping (Bool) -> Void) {
        self.onStop = onStop
    }

    func animationDidStop(_ animation: CAAnimation, finished: Bool) {
        onStop(finished)
    }
}

final class NotchSurfaceLayerView: NSView {
    private enum AnimationKey {
        static let path = "notchSurfacePath"
        static let shadowPath = "notchSurfaceShadowPath"
        static let shadowOpacity = "notchSurfaceShadowOpacity"
    }

    private let surfaceLayer = CAShapeLayer()
    private var configuration: NotchSurfaceConfiguration?
    private var transitionDelegate: NotchTransitionAnimationDelegate?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        layer?.addSublayer(surfaceLayer)

        surfaceLayer.fillColor = NSColor.black.cgColor
        surfaceLayer.masksToBounds = false
        surfaceLayer.shadowColor = NSColor.black.cgColor
        surfaceLayer.shadowOffset = .zero
        surfaceLayer.shadowRadius = 6
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        surfaceLayer.frame = bounds
        surfaceLayer.contentsScale = window?.backingScaleFactor ?? 2

        guard let configuration else { return }
        // SwiftUI can lay out this host repeatedly while the notch is moving.
        // Keep the active presentation path owned by Core Animation until the
        // transition settles; writing the target path here would reset it.
        guard surfaceLayer.animation(forKey: AnimationKey.path) == nil else { return }
        setModelPath(path(for: configuration.isOpen ? 1 : 0, configuration: configuration))
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    fileprivate func update(configuration newConfiguration: NotchSurfaceConfiguration) {
        let previousConfiguration = configuration
        configuration = newConfiguration

        guard bounds.width > 0, bounds.height > 0 else { return }
        guard let previousConfiguration else {
            surfaceLayer.shadowOpacity = newConfiguration.shadowEnabled ? 0.7 : 0
            setModelPath(path(for: newConfiguration.isOpen ? 1 : 0, configuration: newConfiguration))
            return
        }

        guard previousConfiguration.isOpen != newConfiguration.isOpen else {
            let transitionRunning = surfaceLayer.animation(forKey: AnimationKey.path) != nil
            if !transitionRunning {
                surfaceLayer.shadowOpacity = newConfiguration.shadowEnabled ? 0.7 : 0
            }
            // A layout/configuration refresh is expected during a transition.
            // Do not replace the model path while the presentation path is
            // still animating, otherwise the shell visibly stalls or jumps.
            if previousConfiguration != newConfiguration, !transitionRunning {
                setModelPath(path(for: newConfiguration.isOpen ? 1 : 0, configuration: newConfiguration))
            }
            return
        }

        surfaceLayer.shadowOpacity = previousConfiguration.shadowEnabled ? 0.7 : 0

        animate(
            from: currentProgress(configuration: newConfiguration),
            to: newConfiguration.isOpen ? 1 : 0,
            configuration: newConfiguration
        )
    }

    private func animate(
        from start: CGFloat,
        to target: CGFloat,
        configuration: NotchSurfaceConfiguration
    ) {
        let currentShadowOpacity = (surfaceLayer.presentation() as? CAShapeLayer)?.shadowOpacity
            ?? surfaceLayer.shadowOpacity

        surfaceLayer.removeAnimation(forKey: AnimationKey.path)
        surfaceLayer.removeAnimation(forKey: AnimationKey.shadowPath)
        surfaceLayer.removeAnimation(forKey: AnimationKey.shadowOpacity)
        transitionDelegate = nil

        let response: TimeInterval = target == 1 ? 0.42 : 0.45
        let dampingFraction: CGFloat = target == 1 ? 0.8 : 1
        // Keep sampling after the response period so the spring visibly settles.
        let settlingDuration = response * (target == 1 ? 1.2 : 1.5)
        let frameCount = max(2, Int(ceil(settlingDuration * 120)))
        let paths: [CGPath] = (0...frameCount).map { frame in
            if frame == frameCount {
                return path(for: target, configuration: configuration)
            }

            let elapsed = settlingDuration * Double(frame) / Double(frameCount)
            let spring = springProgress(
                elapsed: elapsed,
                response: response,
                dampingFraction: dampingFraction
            )
            return path(
                for: start + (target - start) * spring,
                configuration: configuration
            )
        }

        let animation = CAKeyframeAnimation(keyPath: "path")
        animation.values = paths
        animation.keyTimes = (0...frameCount).map {
            NSNumber(value: Double($0) / Double(frameCount))
        }
        animation.duration = settlingDuration
        animation.calculationMode = .linear
        animation.isRemovedOnCompletion = true

        let startPath = path(for: start, configuration: configuration)
        let targetPath = path(for: target, configuration: configuration)
        let shadowOpacity = configuration.shadowEnabled ? Float(0.7) : 0

        transitionDelegate = NotchTransitionAnimationDelegate { [weak self] finished in
            guard finished, let self else { return }
            self.setModelPath(targetPath)
            self.surfaceLayer.shadowOpacity = shadowOpacity
            self.transitionDelegate = nil
        }
        animation.delegate = transitionDelegate

        // The SwiftUI mask switches to the destination size immediately, so
        // keep the fill model at the destination to cover that content while
        // the presentation path animates. The shadow must remain at the
        // visible start path until its own animation begins, otherwise a
        // one-frame gray halo appears in the not-yet-expanded area.
        setModelPath(targetPath, shadowPath: startPath)
        surfaceLayer.add(animation, forKey: AnimationKey.path)

        let shadowAnimation = CAKeyframeAnimation(keyPath: "shadowPath")
        shadowAnimation.values = paths
        shadowAnimation.keyTimes = animation.keyTimes
        shadowAnimation.duration = settlingDuration
        shadowAnimation.calculationMode = .linear
        shadowAnimation.isRemovedOnCompletion = true
        surfaceLayer.add(shadowAnimation, forKey: AnimationKey.shadowPath)

        surfaceLayer.shadowOpacity = currentShadowOpacity

        let opacityAnimation = CABasicAnimation(keyPath: "shadowOpacity")
        opacityAnimation.fromValue = currentShadowOpacity
        opacityAnimation.toValue = shadowOpacity
        opacityAnimation.duration = settlingDuration
        opacityAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
        opacityAnimation.isRemovedOnCompletion = true
        surfaceLayer.add(opacityAnimation, forKey: AnimationKey.shadowOpacity)
    }

    private func currentProgress(configuration: NotchSurfaceConfiguration) -> CGFloat {
        guard let currentPath = (surfaceLayer.presentation() as? CAShapeLayer)?.path
            ?? surfaceLayer.path
        else {
            return configuration.isOpen ? 1 : 0
        }

        let width = currentPath.boundingBoxOfPath.width
        let distance = configuration.openSize.width - configuration.closedSize.width
        guard abs(distance) > .ulpOfOne else { return configuration.isOpen ? 1 : 0 }
        return min(1, max(0, (width - configuration.closedSize.width) / distance))
    }

    private func setModelPath(_ path: CGPath, shadowPath: CGPath? = nil) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceLayer.path = path
        surfaceLayer.shadowPath = shadowPath ?? path
        CATransaction.commit()
    }

    private func path(
        for progress: CGFloat,
        configuration: NotchSurfaceConfiguration
    ) -> CGPath {
        let width = interpolate(
            configuration.closedSize.width,
            configuration.openSize.width,
            progress
        )
        let height = interpolate(
            configuration.closedSize.height,
            configuration.openSize.height,
            progress
        )
        let topCornerRadius = interpolate(
            configuration.closedTopCornerRadius,
            configuration.openTopCornerRadius,
            progress
        )
        let bottomCornerRadius = interpolate(
            configuration.closedBottomCornerRadius,
            configuration.openBottomCornerRadius,
            progress
        )
        let rect = CGRect(
            x: bounds.midX - width / 2,
            y: bounds.minY,
            width: max(0, width),
            height: max(0, height)
        )

        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }

    private func springProgress(
        elapsed: TimeInterval,
        response: TimeInterval,
        dampingFraction: CGFloat
    ) -> CGFloat {
        let angularFrequency = 2 * Double.pi / response
        let damping = Double(dampingFraction)
        if damping >= 1 {
            return 1 - CGFloat(
                (1 + angularFrequency * elapsed)
                    * exp(-angularFrequency * elapsed)
            )
        }

        let dampedFrequency = angularFrequency * sqrt(1 - damping * damping)
        let decay = exp(-damping * angularFrequency * elapsed)
        let displacement = decay * (
            cos(dampedFrequency * elapsed)
                + damping * angularFrequency / dampedFrequency
                    * sin(dampedFrequency * elapsed)
        )
        return 1 - CGFloat(displacement)
    }

    private func interpolate(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }
}

#Preview {
    NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        .frame(width: 200, height: 32)
        .padding(10)
}
