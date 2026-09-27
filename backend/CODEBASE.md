# Backend Domain Guidelines (Firebase/Workers)

## Overview
This directory contains the backend services for Janarym AI, including Firebase Cloud Functions and Cloudflare Workers.

## Architecture
- **functions/**: Firebase Cloud Functions (Node.js).
- **workers/**: Cloudflare Workers (e.g., `openai-proxy`).

## Guidelines
- Use Node.js for Firebase Functions.
- Use Cloudflare Workers for edge computing tasks like the OpenAI proxy.
- Manage dependencies using `npm` or `yarn`.
- Ensure all API keys and secrets are stored securely using environment variables or secret managers (e.g., `wrangler secret`).
- Write unit tests for critical backend logic.
- Follow RESTful API design principles where applicable.
