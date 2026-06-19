#!/usr/bin/env ruby
# Register a source file with an Xcode target (explicit-reference projects).
# Usage: ruby Scripts/xcp_add.rb <relative/path/to/File.swift> <TargetName>
# Idempotent: re-running is a no-op if the file is already a member.
require 'xcodeproj'

file_rel   = ARGV[0] or abort("usage: xcp_add.rb <file> <target>")
target_nm  = ARGV[1] or abort("usage: xcp_add.rb <file> <target>")
proj_path  = 'Glutt.xcodeproj'

project = Xcodeproj::Project.open(proj_path)
target  = project.targets.find { |t| t.name == target_nm } or abort("target '#{target_nm}' not found")
abs     = File.expand_path(file_rel)
abort("file does not exist: #{abs}") unless File.exist?(abs)

ref = project.files.find { |f| f.real_path.to_s == abs }
if ref.nil?
  group = project.main_group.find_subpath(File.dirname(file_rel), true)
  ref   = group.new_reference(abs)
end

unless target.source_build_phase.files_references.include?(ref)
  target.add_file_references([ref])
end

project.save
puts "registered #{file_rel} -> #{target_nm}"
