# Firmware Domain Guidelines (ESP32)

## Overview
This directory contains the firmware for the ESP32 hardware component of Janarym AI. It is built using PlatformIO.

## Architecture
- **src/**: Main source code files (`main.cpp`, `secrets.h`).
- **include/**: Header files.
- **lib/**: Custom libraries.
- **test/**: Unit tests for firmware.

## Guidelines
- Use PlatformIO for building and managing dependencies.
- Keep `secrets.h` out of version control (ensure it's in `.gitignore`).
- Optimize for low memory and power consumption.
- Document hardware pinouts and connections clearly.
- Follow C++ best practices for embedded systems.
