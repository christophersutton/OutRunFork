#!/usr/bin/env ruby
# Adds source files to an Xcode target (project uses objectVersion 51 — explicit file refs).
# Usage: ruby add_files_to_target.rb <project.xcodeproj> <TargetName> <relative/file1.swift> [file2.swift ...]
# Run with CocoaPods' vendored xcodeproj gem, e.g.:
#   GEM_HOME=/opt/homebrew/Cellar/cocoapods/1.16.2_2/libexec ruby scripts/add_files_to_target.rb ...
require 'xcodeproj'

proj_path, target_name, *files = ARGV
abort("usage: add_files_to_target.rb <proj> <target> <files...>") if proj_path.nil? || target_name.nil? || files.empty?

project = Xcodeproj::Project.open(proj_path)
target = project.targets.find { |t| t.name == target_name } or abort("target #{target_name} not found")

existing = project.files.map { |f| f.real_path.to_s }

files.each do |rel|
  abs = File.expand_path(rel)
  if existing.include?(abs)
    puts "skip (already in project): #{rel}"
    next
  end
  group_path = File.dirname(rel)               # e.g. OutRun/Models/Data/Snapshots
  group = project.main_group.find_subpath(group_path, true)
  group.set_source_tree('SOURCE_ROOT')
  ref = group.new_reference(abs)
  target.source_build_phase.add_file_reference(ref, true)
  puts "added: #{rel}"
end

project.save
puts "saved #{proj_path}"
