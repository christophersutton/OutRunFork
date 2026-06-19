#!/usr/bin/env ruby
# Removes source-file references (and their build-phase entries) from an Xcode project.
# Usage: ruby remove_files_from_target.rb <project.xcodeproj> <relative/file1.swift> [file2.swift ...]
# Run with the same vendored xcodeproj gem as add_files_to_target.rb.
require 'xcodeproj'

proj_path, *files = ARGV
abort("usage: remove_files_from_target.rb <proj> <files...>") if proj_path.nil? || files.empty?

project = Xcodeproj::Project.open(proj_path)

files.each do |rel|
  abs = File.expand_path(rel)
  refs = project.files.select { |f| f.real_path.to_s == abs }
  if refs.empty?
    puts "skip (not in project): #{rel}"
    next
  end
  refs.each(&:remove_from_project)   # also clears build_files
  puts "removed: #{rel}"
end

project.save
puts "saved #{proj_path}"
