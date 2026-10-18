//
//  MetalSprocketsParticlesDemoApp.swift
//  MetalSprocketsParticlesDemo
//
//  Created by Jonathan Wight.
//

import MetalSprocketsParticlesDemoSupport
import SwiftUI

@main
struct MetalSprocketsParticlesDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        Window("2D Overlay", id: OverlayDemoView.windowID) {
            OverlayDemoView()
                .frame(minWidth: 500, minHeight: 400)
        }
    }
}