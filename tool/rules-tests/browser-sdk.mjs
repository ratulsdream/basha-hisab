// Test-only, integrity-locked npm SDK matching firebase_core_web 3.12.0.
// Never bundled into the Android/iOS app or pointed at a production project.
import * as core from 'firebase/app';
import * as auth from 'firebase/auth';
import * as firestore from 'firebase/firestore';
import * as pipelines from 'firebase/firestore/pipelines';
import * as messaging from 'firebase/messaging';
globalThis.firebase_core = core;
globalThis.firebase_auth = auth;
// The npm pipelines entry exports fewer standard APIs than its CDN bundle.
// Preserve the genuine standard API (including memoryLocalCache) alongside pipelines.
globalThis.firebase_firestore = {...pipelines, ...firestore};
globalThis.firebase_messaging = messaging;
