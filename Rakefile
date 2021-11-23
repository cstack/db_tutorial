require "bundler/setup"
require "jekyll/task/i18n"

Jekyll::Task::I18n.define do |task|
  # Locales set japanese
  task.locales = ["ja"]
  task.files = Rake::FileList["**/*.md"]
  task.files += Rake::FileList["_parts/*.md"]
  task.files += Rake::FileList["_layouts/*.html"]
  task.files -= Rake::FileList["_layouts/**/*.md"]
  task.files -= Rake::FileList["_includes/**/*.md"]
  task.files -= Rake::FileList["_site/**/*.md"]
  task.files -= Rake::FileList["_site/**/*.html"]

  task.locales.each do |locale|
    task.files -= Rake::FileList["#{locale}/**/*.md"]
  end
end

task :default => "jekyll:i18n:translate"