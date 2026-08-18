#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds (or repairs) the watchOS companion target in Runner.xcodeproj.
#
# Flutter owns `ios/Runner.xcodeproj`, and a hand-edited project file is the
# first thing to break when the tooling regenerates or a merge goes sideways.
# This script is the source of truth instead: run it and the project is put
# back into the state described here, whatever it was in before.
#
#   gem install xcodeproj
#   ruby ios/tool/add_watch_target.rb
#
# What it does:
#   * compiles ios/Runner/WatchBridge.swift into the Runner target,
#   * creates the `YourLMWatch` watchOS app target from ios/YourLMWatch/,
#   * makes Runner depend on it and embed it under Watch/ in the .app,
#   * writes a shared scheme so the watch app can be run from Xcode.
#
# It is idempotent: an existing YourLMWatch target is torn out and rebuilt.

require 'xcodeproj'

ROOT = File.expand_path('../..', __dir__)
PROJECT_PATH = File.join(ROOT, 'ios', 'Runner.xcodeproj')

WATCH_TARGET = 'YourLMWatch'
WATCH_DIR = 'YourLMWatch'
IOS_BUNDLE_ID = 'com.leveleightyfour.YourLaunchMonitor'
WATCH_BUNDLE_ID = "#{IOS_BUNDLE_ID}.watchkitapp"
DEVELOPMENT_TEAM = 'VGUWC2L7S2'
WATCHOS_DEPLOYMENT_TARGET = '9.0'
EMBED_PHASE_NAME = 'Embed Watch Content'

project = Xcodeproj::Project.open(PROJECT_PATH)
runner = project.targets.find { |t| t.name == 'Runner' } or abort 'No Runner target found.'

# ── 1. The iPhone side of the link ────────────────────────────────────────────

runner_group = project.main_group['Runner']
bridge_ref = runner_group.files.find { |f| f.path == 'WatchBridge.swift' }
bridge_ref ||= runner_group.new_reference('WatchBridge.swift')
unless runner.source_build_phase.files_references.include?(bridge_ref)
  runner.source_build_phase.add_file_reference(bridge_ref)
end

# ── 2. Remove any previous watch target, so this script can be re-run ─────────
#
# Everything the target owns goes with it. A half-removed target leaves
# orphaned build phases and configuration lists behind in the project file,
# which Xcode carries around forever without ever mentioning.

project.targets.select { |t| t.name == WATCH_TARGET }.each do |stale|
  runner.dependencies.select { |d| d.target == stale }.each do |dependency|
    dependency.target_proxy&.remove_from_project
    dependency.remove_from_project
  end
  stale.build_phases.each do |phase|
    phase.files.each(&:remove_from_project)
    phase.remove_from_project
  end
  stale.build_configuration_list.build_configurations.each(&:remove_from_project)
  stale.build_configuration_list.remove_from_project
  stale.product_reference&.remove_from_project
  stale.remove_from_project
end

runner.build_phases
      .select { |p| p.respond_to?(:name) && p.name == EMBED_PHASE_NAME }
      .each do |phase|
        phase.files.each(&:remove_from_project)
        phase.remove_from_project
      end

[WATCH_DIR, 'Frameworks'].each do |name|
  group = project.main_group[name]
  next unless group

  group.recursive_children.each(&:remove_from_project)
  group.remove_from_project
end

# ── 3. The watch app target ───────────────────────────────────────────────────

watch = project.new_target(
  :application, WATCH_TARGET, :watchos, WATCHOS_DEPLOYMENT_TARGET, nil, :swift
)

watch_group = project.main_group.new_group(WATCH_DIR, WATCH_DIR)
Dir.glob(File.join(ROOT, 'ios', WATCH_DIR, '*.swift')).sort.each do |path|
  watch.source_build_phase.add_file_reference(watch_group.new_reference(File.basename(path)))
end
watch.resources_build_phase.add_file_reference(watch_group.new_reference('Assets.xcassets'))
watch_group.new_reference('Info.plist')

# Xcodeproj links Foundation by absolute path into whichever watchOS SDK
# happens to be installed here — a path that is wrong on the next machine.
# Swift auto-links it anyway, so the phase and the group it created go.
watch.frameworks_build_phase.files.each(&:remove_from_project)
if (frameworks = project.main_group['Frameworks'])
  frameworks.recursive_children.each(&:remove_from_project)
  frameworks.remove_from_project
end

# Version and build number come from Flutter, exactly as the iPhone app's do —
# the App Store rejects a watch app whose version drifts from its companion.
generated_xcconfig = project.main_group['Flutter'].files.find { |f| f.display_name == 'Generated.xcconfig' }

watch.build_configurations.each do |config|
  config.base_configuration_reference = generated_xcconfig if generated_xcconfig
  config.build_settings.merge!(
    # Xcodeproj defaults this on for application targets. A watch app nested
    # inside an iPhone app must not carry its own copy of the Swift runtime —
    # App Store validation rejects the duplicate.
    'ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES' => 'NO',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
    'CLANG_ENABLE_MODULES' => 'YES',
    # Automatic, unlike the iPhone target: a prototype should install on a
    # paired watch without anyone having to mint a provisioning profile first.
    'CODE_SIGN_STYLE' => 'Automatic',
    'DEVELOPMENT_TEAM' => DEVELOPMENT_TEAM,
    'ENABLE_PREVIEWS' => 'YES',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'INFOPLIST_FILE' => "#{WATCH_DIR}/Info.plist",
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks'],
    'PRODUCT_BUNDLE_IDENTIFIER' => WATCH_BUNDLE_ID,
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'SDKROOT' => 'watchos',
    # Embedded in the iPhone app, so it must not be installed or archived on
    # its own.
    'SKIP_INSTALL' => 'YES',
    'SUPPORTED_PLATFORMS' => 'watchos watchsimulator',
    'SWIFT_VERSION' => '5.0',
    'TARGETED_DEVICE_FAMILY' => '4',
    'WATCHOS_DEPLOYMENT_TARGET' => WATCHOS_DEPLOYMENT_TARGET
  )
  config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if config.name == 'Debug'
end

# ── 4. Embed it in the iPhone app ─────────────────────────────────────────────

runner.add_dependency(watch)

embed = runner.new_copy_files_build_phase(EMBED_PHASE_NAME)
embed.symbol_dst_subfolder_spec = :products_directory
embed.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
embed_file = embed.add_file_reference(watch.product_reference)
embed_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# Ahead of Flutter's "Thin Binary" phase, which expects a finished bundle.
thin_index = runner.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
if thin_index
  runner.build_phases.delete(embed)
  runner.build_phases.insert(thin_index, embed)
end

# ── 5. A scheme, so the watch app is runnable from Xcode ──────────────────────

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(watch)
scheme.set_launch_target(watch)
scheme.save_as(PROJECT_PATH, WATCH_TARGET, true)

project.save

puts "Added #{WATCH_TARGET} (#{WATCH_BUNDLE_ID}) to Runner.xcodeproj"
puts "  sources:   ios/#{WATCH_DIR}/*.swift"
puts "  embedded:  Runner.app/Watch/#{WATCH_TARGET}.app"
