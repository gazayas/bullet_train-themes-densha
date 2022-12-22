require "io/wait"

namespace :bt do
  desc "Symlink registered gems in `./tmp/gems` so their views, etc. can be inspected by Tailwind CSS."
  task link: :environment do
    if Dir.exist?("tmp/gems")
      puts "Removing previously linked gems."
      `rm -f tmp/gems/*`
    else
      if File.exist?("tmp/gems")
        raise "A file named `tmp/gems` already exists? It has to be removed before we can create the required directory."
      end

      puts "Creating 'tmp/gems' directory."
      `mkdir tmp/gems`
    end

    `touch tmp/gems/.keep`

    BulletTrain.linked_gems.each do |linked_gem|
      target = `bundle show #{linked_gem}`.chomp
      if target.present?
        puts "Linking '#{linked_gem}' to '#{target}'."
        `ln -s #{target} tmp/gems/#{linked_gem}`
      end
    end
  end
end

namespace :bullet_train do
  desc "Figure out where something is coming from."
  task :resolve, [:all_options] => :environment do |t, arguments|
    ARGV.pop while ARGV.any?

    arguments[:all_options]&.split&.each do |argument|
      ARGV.push(argument)
    end

    if ARGV.include?("--interactive")
      puts "\nOK, paste what you've got for us and hit <Return>!\n".blue

      input = $stdin.gets.strip
      $stdin.getc while $stdin.ready?

      # Extract absolute paths from annotated views.
      if input =~ /<!-- BEGIN (.*) -->/
        input = $1
      end

      # Append the main application's path if the file is a local file.
      # i.e. - app/views/layouts/_head.html.erb
      if input.match?(/^app/)
        input = "#{Rails.root}/#{input}"
      end

      ARGV.unshift input.strip
    end

    if ARGV.first.present?
      BulletTrain::Resolver.new(ARGV.first).run(eject: ARGV.include?("--eject"), open: ARGV.include?("--open"), force: ARGV.include?("--force"), interactive: ARGV.include?("--interactive"))
    else
      warn <<~MSG
        🚅 Usage: #{"`bin/resolve [path, partial, or URL] (--eject) (--open)`".blue}

        OR

        #{"`bin/resolve --interactive`".blue}
        When you use the interactive flag, we will prompt you to pass an annotated partial like so and either eject or open the file.
        These annotated paths can be found in your browser when inspecting elements:
        <!-- BEGIN /your/path/.rbenv/versions/3.1.2/lib/ruby/gems/3.1.0/gems/bullet_train-themes-light-1.0.51/app/views/themes/light/_notices.html.erb -->
      MSG
    end
  end

  task :develop, [:all_options] => :environment do |t, arguments|
    def stream(command, prefix = "  ")
      puts ""

      begin
        trap("SIGINT") { throw :ctrl_c }

        IO.popen(command) do |io|
          while (line = io.gets)
            puts "#{prefix}#{line}"
          end
        end
      rescue UncaughtThrowError
        puts "Received a <Control + C>. Exiting the child process.".blue
      end

      puts ""
    end

    framework_packages = I18n.t("framework_packages")

    # Process any flags that were passed.
    if arguments[:all_options].present?
      flags_with_values = []

      arguments[:all_options].split(/\s+/).each do |option|
        if option.match?(/^--/)
          flags_with_values << {flag: option, values: []}
        else
          flags_with_values.last[:values] << option
        end
      end

      if flags_with_values.any?
        flags_with_values.each do |process|
          case process[:flag]
          when "--help"
            puts "bin/hack: Clone bullet_train-core and link up gems (will only link up gems if already cloned).".blue
            puts "bin/hack --link: Link all of your Bullet Train gems to `local/bullet_train-core`".blue
            puts "bin/hack --reset: Resets all of your gems to their original definition.".blue
            puts "bin/hack --watch-js: Watches for any changes in JavaScript files gems that have an npm package.".blue
            puts "bin/hack --clean-js: Resets all of your npm packages from `local/bullet_train-core` to their original definition".blue
            exit
          when "--link", "--reset"
            set_core_gems(process[:flag], framework_packages)
            stream "bundle install"
          when "--watch-js"
            set_npm_packages(process[:flag], framework_packages)

            puts "Proceeding to reset your Bullet Train npm packages according to your root directory's `package.json`.".yellow
            puts "If you press `Ctrl + C` before the process completely exits, just run `bin/hack --clean-js`".yellow
            set_npm_packages("--clean-js", framework_packages)
            break
          when "--clean-js"
            set_npm_packages(process[:flag], framework_packages)
            break
          end
        end

        exit
      end
    end

    puts "Welcome! Let's get hacking.".blue

    # Adding these flags enables us to execute git commands in the gem from our starter repo.
    work_tree_flag = "--work-tree=local/bullet_train-core"
    git_dir_flag = "--git-dir=local/bullet_train-core/.git"

    if File.exist?("local/bullet_train-core")
      puts "We found the repository in `local/bullet_train-core`. We will try to use what's already there.".yellow
      puts ""

      git_status = `git #{work_tree_flag} #{git_dir_flag} status`
      unless git_status.match?("nothing to commit, working tree clean")
        puts "This package currently has uncommitted changes.".red
        puts "Please make sure the branch is clean and try again.".red
        exit
      end

      current_branch = `git #{work_tree_flag} #{git_dir_flag} branch`.split("\n").select { |branch_name| branch_name.match?(/^\*\s/) }.pop.gsub(/^\*\s/, "")
      unless current_branch == "main"
        puts "Previously on #{current_branch}.".blue
        puts "Switching local/bullet_train-core to main branch.".blue
        stream("git #{work_tree_flag} #{git_dir_flag} checkout main")
      end

      puts "Updating the main branch with the latest changes.".blue
      stream("git #{work_tree_flag} #{git_dir_flag} pull origin main")
    else
      # Use https:// URLs when using this task in Gitpod.
      stream "git clone #{(`whoami`.chomp == "gitpod") ? "https://github.com/" : "git@github.com:"}/bullet-train-co/bullet_train-core.git local/bullet_train-core"
    end

    stream("git #{work_tree_flag} #{git_dir_flag} fetch")
    stream("git #{work_tree_flag} #{git_dir_flag} branch -r")
    puts "The above is a list of remote branches.".blue
    puts "If there's one you'd like to work on, please enter the branch name and press <Enter>.".blue
    puts "If not, just press <Enter> to continue.".blue
    input = $stdin.gets.strip
    unless input.empty?
      puts "Switching to #{input.gsub("origin/", "")}".blue # TODO: Should we remove origin/ here if the developer types it?
      stream("git #{work_tree_flag} #{git_dir_flag} checkout #{input}")
    end

    # Link all of the local gems to the current Gemfile.
    puts "Now we'll try to link up the Bullet Train core repositories in the `Gemfile`.".blue
    set_core_gems("--link", framework_packages)

    puts ""
    puts "Now we'll run `bundle install`.".blue
    stream "bundle install"

    puts ""
    puts "We'll restart any running Rails server now.".blue
    stream "rails restart"

    puts ""
    puts "OK, we're opening bullet_train-core in your IDE, `#{ENV["IDE"] || "code"}`. (You can configure this with `export IDE=whatever`.)".blue
    `#{ENV["IDE"] || "code"} local/bullet_train-core`
    puts ""

    puts "Bullet Train has a few npm packages, so we will and install those now.".blue
    puts "We will also watch for any changes in your JavaScript files and recompile as we go.".blue
    puts "When you're done, you can hit <Control + C> and we'll clean all off this up.".blue
    puts ""
    set_npm_packages("--watch-js", framework_packages)

    # Clean up the npm packages after the developer enters `Ctrl + C`.
    puts "Cleaning up npm packages...".blue
    puts "If you cancel out of this process early, just run `bin/hack --clean-js` to revert to your original npm packages.".blue
    set_npm_packages("--clean-js", framework_packages)

    puts ""
    puts "OK, here's a list of things this script still doesn't do you for you:".yellow
    puts "1. It doesn't clean up the repository that was cloned into `local`.".yellow
    puts "2. Unless you remove it, it won't update that repository the next time you link to it.".yellow
  end

  # Pass "--link" or "--reset" as a flag to set the gems.
  def set_core_gems(flag, framework_packages)
    packages = framework_packages.keys
    gemfile_lines = File.readlines("./Gemfile")
    new_lines = gemfile_lines.map do |line|
      packages.each do |package|
        if line.match?(/"#{package}"/)
          original_path = "gem \"#{package}\""
          local_path = "gem \"#{package}\", path: \"local/bullet_train-core/#{package}\""

          case flag
          when "--link"
            if `cat Gemfile | grep "gem \\\"#{package}\\\", path: \\\"local/#{package}\\\""`.chomp.present?
              puts "#{package} is already linked to a checked out copy in `local` in the `Gemfile`.".green
            elsif `cat Gemfile | grep "gem \\\"#{package}\\\","`.chomp.present?
              puts "#{package} already has some sort of alternative source configured in the `Gemfile`.".yellow
              puts "We can't do anything with this. Sorry! We'll proceed, but you have to link this package yourself.".red
            elsif `cat Gemfile | grep "gem \\\"#{package}\\\""`.chomp.present?
              puts "#{package} is directly present in the `Gemfile`, so we'll update that line.".green
              line.gsub!(original_path, local_path)
            end
            break
          when "--reset"
            line.gsub!(local_path, original_path)
            puts "Resetting '#{package}' package in the Gemfile...".blue
            break
          end
        end
      end
      line
    end

    File.write("./Gemfile", new_lines.join)
  end

  def set_npm_packages(flag, framework_packages)
    packages = framework_packages.select { |k, v| v[:npm].present? }.compact

    if flag == "--watch-js"
      puts "Make sure your server is running before proceeding. When you're ready, press <Enter>".blue
      $stdin.gets.strip

      puts "Linking npm packages...".blue
      puts ""

      yarn_watch_command = []
      packages.each do |package_name, details|
        puts "Linking JavaScript for #{package_name}".blue
        stream "cd local/bullet_train-core/#{package_name} && yarn install && npm_config_yes=true && npx yalc link && cd ../../.. && npm_config_yes=true npx yalc link \"#{details[:npm]}\""
        puts "#{package_name} has been linked.".blue
        puts ""
        yarn_watch_command << "yarn --cwd local/bullet_train-core/#{package_name} watch"
      end

      # We use `&` to run the processes in parallel.
      puts "Preparing to watch changes".blue
      stream yarn_watch_command.join(" & ")
    elsif flag == "--clean-js"
      puts "Resetting packages to their original path".blue
      puts ""

      packages.each do |package_name, details|
        system "yarn yalc remove #{details[:npm]}"
        system "yarn add #{details[:npm]}"
      end
    end
  end
end