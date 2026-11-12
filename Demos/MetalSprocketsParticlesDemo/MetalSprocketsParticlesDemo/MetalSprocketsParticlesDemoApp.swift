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
        #if os(visionOS)
        ImmersiveSpace(id: ImmersiveParticlesContent.spaceID) {
            ImmersiveParticlesContent()
        }
        // Mixed: the effect plays in the room.
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        #endif
    }
}