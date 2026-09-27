# Mobile Domain Guidelines (iOS)

## Overview
This directory contains the iOS application for Janarym AI. It is built using SwiftUI and Swift.

## Architecture
- **App/**: Application entry point, root view, lifecycle management.
- **Core/**: Configuration, enums, utilities, and core logic.
- **Features/**: Feature modules (Assistant, Camera, Modes, Permissions, etc.).
- **Services/**: External services integration (OpenAI, Speech, Firebase, BLE, ESP32Camera).
- **Resources/**: Assets, Info.plist, Secrets.

## Guidelines
- Use SwiftUI for all new UI components.
- Follow the MVVM or similar reactive pattern suitable for SwiftUI.
- Ensure all secrets are loaded from `Secrets.plist` and never hardcoded.
- Test camera and microphone features on a real device, as simulators have limitations.
- Keep the UI responsive and accessible.
