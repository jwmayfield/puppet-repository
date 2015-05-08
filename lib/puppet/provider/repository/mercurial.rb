require 'fileutils'
require 'puppet/util/errors'
require 'puppet/util/execution'
require 'shellwords'

Puppet::Type.type(:repository).provide :mercurial do
  include Puppet::Util::Execution
  include Puppet::Util::Errors

  optional_commands :mercurial => 'hg'

  def self.default_protocol
    'https'
  end

  def query
    h = { :name => @resource[:name], :provider => :mercurial }

    if cloned?
      if [:present, :absent].member? @resource[:ensure]
        h.merge(:ensure => :present)
      else
        if correct_revision?
          h.merge(:ensure => @resource[:ensure])
        else
          # we need to ensure the correct revision, cheat #exists?
          h.merge(:ensure => current_revision)
        end
      end
    else
      h.merge(:ensure => :absent)
    end
  end

  def create
    command = [
      command(:mercurial),
      "clone",
      friendly_config,
      friendly_extra,
      friendly_source,
      friendly_path
    ].flatten.compact.join(' ')

    execute command, command_opts
  end

  def ensure_revision
    create unless cloned?

    Dir.chdir @resource[:path] do
      status = execute [command(:mercurial), "status"], command_opts

      if status.empty?
        execute [command(:mercurial), "update", "-C", target_revision], command_opts
      else
        if @resource[:force]
          Puppet.warning("Repository[#{@resource[:name]}] tree is dirty and force is true: doing hard reset!")
          execute [command(:mercurial), "update", "-C", target_revision], command_opts
        else
          fail("Repository[#{@resource[:name]}] tree is dirty and force is false: cannot sync resource!")
        end
      end
    end
  end

  def destroy
    FileUtils.rm_rf @resource[:path]
  end

  def expand_source(source)
    if source =~ /\A[^@\/\s]+\/[^\/\s]+\z/
      "#{@resource[:protocol]}://bitbucket.com/#{source}"
    else
      source
    end
  end

  def command_opts
    @command_opts ||= build_command_opts
  end

  def build_command_opts
    default_command_opts.tap do |h|
      if uid = (@resource[:user] || self.class.default_user)
        h[:uid] = uid
      end
    end
  end

  def default_command_opts
    {
      :combine     => true,
      :failonfail  => true
    }
  end

  def friendly_config
  end

  def friendly_extra
  end

  def friendly_source
    @friendly_source ||= expand_source(@resource[:source])
  end

  def friendly_path
    @friendly_path ||= Shellwords.escape(@resource[:path])
  end

  private

  def current_revision
    @current_revision ||= Dir.chdir @resource[:path] do
      execute([
               command(:mercurial), "parents",
               "--template", "{node}"
      ], command_opts)
    end
  end

  def target_revision
    @target_revision ||= Dir.chdir @resource[:path] do
      execute([
        command(:mercurial), "log", "--template", "{node}", "-r", @resource[:ensure]
      ], command_opts).chomp
    end
  end

  def cloned?
    File.directory?(@resource[:path]) &&
      File.directory?("#{@resource[:path]}/.hg")
  end

  def correct_revision?
    Dir.chdir @resource[:path] do
      execute [
        command(:mercurial), "pull",
      ], command_opts

      current_revision == target_revision
    end
  end
end
