#!/usr/bin/env ruby
# setup-ec-extensions.rb
#
# Injects EasyClick extensions into the WebDriverAgent Xcode project:
# 1. Adds iosauto.framework to WebDriverAgentLib (link) and WebDriverAgentRunner (embed)
# 2. Adds FBEC*.m source files to WebDriverAgentLib
# 3. Adds FBECResponsePayload.m to WebDriverAgentLib
# 4. Adds ML model resources to WebDriverAgentRunner
# 5. Updates FRAMEWORK_SEARCH_PATHS
# 6. Adds CODE_SIGN_ENTITLEMENTS reference
#
# Usage: ruby Scripts/ci/setup-ec-extensions.rb

require 'xcodeproj'
require 'securerandom'

PROJECT_PATH = File.join(File.dirname(__FILE__), '..', '..', 'WebDriverAgent.xcodeproj')

def hex24
  SecureRandom.hex(12).upcase
end

puts "=== Setting up EasyClick extensions ==="
puts "Project: #{PROJECT_PATH}"

project = Xcodeproj::Project.open(PROJECT_PATH)

# Find targets
wda_lib = project.targets.find { |t| t.name == 'WebDriverAgentLib' }
wda_runner = project.targets.find { |t| t.name == 'WebDriverAgentRunner' }

unless wda_lib && wda_runner
  puts "ERROR: Could not find WebDriverAgentLib or WebDriverAgentRunner targets"
  exit 1
end

puts "Found targets: #{wda_lib.name}, #{wda_runner.name}"

# ============================================================
# 1. Add iosauto.framework
# ============================================================
puts "\n[1/6] Adding iosauto.framework..."

# Check if already added
iosauto_ref = project.files.find { |f| f.path && f.path.include?('iosauto.framework') }
if iosauto_ref
  puts "  iosauto.framework already in project, skipping"
else
  # Add file reference at project root
  iosauto_ref = project.main_group.new_file('iosauto.framework')

  # Add to WebDriverAgentLib Frameworks build phase (link)
  wda_lib.frameworks_build_phase.add_file_reference(iosauto_ref)

  # Add to WebDriverAgentRunner Copy Files phase (embed with code signing)
  copy_phase = wda_runner.copy_files_build_phases.find { |p| p.name == 'Copy frameworks' }
  if copy_phase
    build_file = copy_phase.add_file_reference(iosauto_ref)
    build_file.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
    puts "  Added to Copy frameworks phase with CodeSignOnCopy"
  else
    puts "  WARNING: Copy frameworks phase not found"
  end

  puts "  iosauto.framework added"
end

# ============================================================
# 2. Add FBEC source files
# ============================================================
puts "\n[2/6] Adding FBEC source files..."

fbec_files = [
  'WebDriverAgentLib/Commands/FBECColorCommands.m',
  'WebDriverAgentLib/Commands/FBECDeviceCommands.m',
  'WebDriverAgentLib/Commands/FBECIMECommands.m',
  'WebDriverAgentLib/Commands/FBECOCRCommands.m',
  'WebDriverAgentLib/Commands/FBECScreenCommands.m',
  'WebDriverAgentLib/Commands/FBECTemplateCommands.m',
  'WebDriverAgentLib/Commands/FBECYoloCommands.m',
  'WebDriverAgentLib/Routing/FBECResponsePayload.m',
]

# Check existing source files in the build phase
existing_sources = wda_lib.source_build_phase.files.map { |f| f.file_ref&.path }.compact

fbec_files.each do |file_path|
  filename = File.basename(file_path)

  if existing_sources.any? { |s| s && s.include?(filename) }
    puts "  #{filename} already in Sources, skipping"
    next
  end

  # Check file exists on disk
  full_path = File.join(File.dirname(__FILE__), '..', '..', file_path)
  unless File.exist?(full_path)
    puts "  WARNING: #{file_path} not found on disk, skipping"
    next
  end

  # Find or create group
  group_path = File.dirname(file_path)
  group = project.main_group.find_subpath(group_path, true)

  # Add file reference
  file_ref = group.new_file(File.basename(file_path))

  # Add to Sources build phase
  wda_lib.source_build_phase.add_file_reference(file_ref)
  puts "  Added #{filename}"
end

# ============================================================
# 3. Add ML model resources
# ============================================================
puts "\n[3/6] Adding ML model resources..."

resource_dirs = [
  'Resources/ocrlite/model',
  'Resources/paddlelite_models/v5',
]

resource_files = []

resource_dirs.each do |dir|
  full_dir = File.join(File.dirname(__FILE__), '..', '..', dir)
  unless Dir.exist?(full_dir)
    puts "  WARNING: #{dir} not found, skipping"
    next
  end

  Dir.glob(File.join(full_dir, '*')).each do |file|
    next if File.directory?(file)
    rel_path = File.join(dir, File.basename(file))
    resource_files << rel_path
  end
end

existing_resources = wda_runner.resources_build_phase.files.map { |f| f.file_ref&.path }.compact

resource_files.each do |file_path|
  filename = File.basename(file_path)

  if existing_resources.any? { |s| s && s.include?(filename) }
    puts "  #{filename} already in Resources, skipping"
    next
  end

  # Create group hierarchy
  group_path = File.dirname(file_path)
  group = project.main_group.find_subpath(group_path, true)

  file_ref = group.new_file(File.basename(file_path))
  wda_runner.resources_build_phase.add_file_reference(file_ref)
  puts "  Added #{filename}"
end

# ============================================================
# 4. Update FRAMEWORK_SEARCH_PATHS for WebDriverAgentLib
# ============================================================
puts "\n[4/6] Updating FRAMEWORK_SEARCH_PATHS..."

wda_lib.build_configurations.each do |config|
  current = config.build_settings['FRAMEWORK_SEARCH_PATHS']
  if current.is_a?(String)
    paths = [current]
  elsif current.is_a?(Array)
    paths = current.dup
  else
    paths = []
  end

  unless paths.include?('$(PROJECT_DIR)')
    paths << '$(PROJECT_DIR)'
    config.build_settings['FRAMEWORK_SEARCH_PATHS'] = paths
    puts "  Added $(PROJECT_DIR) to #{config.name} config"
  end
end

# Also update for WebDriverAgentRunner
wda_runner.build_configurations.each do |config|
  current = config.build_settings['FRAMEWORK_SEARCH_PATHS']
  if current.is_a?(String)
    paths = [current]
  elsif current.is_a?(Array)
    paths = current.dup
  else
    paths = []
  end

  unless paths.include?('$(PROJECT_DIR)')
    paths << '$(PROJECT_DIR)'
    config.build_settings['FRAMEWORK_SEARCH_PATHS'] = paths
    puts "  Added $(PROJECT_DIR) to Runner #{config.name} config"
  end
end

# ============================================================
# 5. Add CODE_SIGN_ENTITLEMENTS
# ============================================================
puts "\n[5/6] Adding CODE_SIGN_ENTITLEMENTS..."

wda_runner.build_configurations.each do |config|
  unless config.build_settings['CODE_SIGN_ENTITLEMENTS']
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'WebDriverAgentRunner/WebDriverAgentRunner.entitlements'
    puts "  Set entitlements for #{config.name}"
  end
end

# ============================================================
# 6. Save project
# ============================================================
puts "\n[6/6] Saving project..."
project.save

puts "\n=== EasyClick extensions setup complete! ==="
puts "Summary:"
puts "  - iosauto.framework: linked + embedded"
puts "  - FBEC source files: #{fbec_files.length} files"
puts "  - ML resources: #{resource_files.length} files"
puts "  - FRAMEWORK_SEARCH_PATHS: updated"
puts "  - CODE_SIGN_ENTITLEMENTS: set"
