#!/usr/bin/env python3
"""Validate native Firebase configs and install them without committing values."""
import argparse
import json
import plistlib
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def copy_if_needed(source, destination):
    if source.resolve() != destination.resolve():
        shutil.copyfile(source, destination)


def configure(android=None, ios=None):
    android_data = None
    ios_data = None
    if android:
        android_data = json.loads(android.read_text())
        matching = [client for client in android_data.get('client', [])
                    if client.get('client_info', {}).get('android_client_info', {}).get('package_name') == 'com.bashahisab.app']
        if not matching:
            raise ValueError('Android Firebase config must include package com.bashahisab.app')
        if not android_data.get('project_info', {}).get('project_id'):
            raise ValueError('Android Firebase config is missing project_id')
        if not matching[0].get('api_key') or not matching[0].get('client_info', {}).get('mobilesdk_app_id'):
            raise ValueError('Android Firebase app ID / API key is missing')
    if ios:
        ios_data = plistlib.loads(ios.read_bytes())
        bundle = ios_data.get('BUNDLE_ID', '')
        if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', bundle):
            raise ValueError('iOS Firebase config is missing a valid BUNDLE_ID')
        if not all(ios_data.get(key) for key in ['GOOGLE_APP_ID', 'API_KEY', 'PROJECT_ID']):
            raise ValueError('iOS Firebase app ID, API key or project ID is missing')
    if android_data and ios_data and android_data['project_info']['project_id'] != ios_data['PROJECT_ID']:
        raise ValueError('Android and iOS configs must use the same Firebase project')
    if android:
        copy_if_needed(android, ROOT / 'android/app/google-services.json')
        print('Android configuration installed for com.bashahisab.app')
    if ios:
        project = ROOT / 'ios/Runner.xcodeproj/project.pbxproj'
        text = project.read_text()
        def replace_bundle(match):
            suffix = '.RunnerTests' if '.RunnerTests' in match[0] else ''
            return f'PRODUCT_BUNDLE_IDENTIFIER = {ios_data["BUNDLE_ID"]}{suffix};'
        text, count = re.subn(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*[^;]+;', replace_bundle, text)
        if count != 6:
            raise ValueError(f'Expected six iOS bundle build settings, found {count}')
        copy_if_needed(ios, ROOT / 'ios/Runner/GoogleService-Info.plist')
        project.write_text(text)
        print('iOS configuration installed; bundle ID set from the supplied plist')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--android', type=Path)
    parser.add_argument('--ios', type=Path)
    args = parser.parse_args()
    if not args.android and not args.ios:
        parser.error('Supply --android google-services.json and/or --ios GoogleService-Info.plist')
    try:
        configure(args.android, args.ios)
    except (ValueError, OSError, KeyError, plistlib.InvalidFileException) as error:
        parser.exit(1, f'Firebase configuration error: {error}\n')
