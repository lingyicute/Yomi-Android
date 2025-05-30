#!/usr/bin/env bash
cd android
bundle install
bundle update fastlane
bundle exec fastlane set_build_code_internal
cd ..
