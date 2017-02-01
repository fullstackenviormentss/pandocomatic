#--
# Copyright 2014, 2015, 2016, 2017, Huub de Beer <Huub@heerdebeer.org>
# 
# This file is part of pandocomatic.
# 
# Pandocomatic is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
# 
# Pandocomatic is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
# 
# You should have received a copy of the GNU General Public License along
# with pandocomatic.  If not, see <http://www.gnu.org/licenses/>.
#++
module Pandocomatic

  require 'yaml'
  require 'paru/pandoc'

  DEFAULT_CONFIG = YAML.load_file File.join(__dir__, 'default_configuration.yaml')

  FORMAT_TO_EXT = {
    'native' => 'hs',
    'markdown_strict' => 'markdown',
    'markdown_phpextra' => 'markdown',
    'markdown_github' => 'markdown',
    'html5' => 'html',
    'docx' => 'docx',
    'latex' => 'tex'
  }

  # Configuration describes a pandocomatic configuration.
  class Configuration

    def initialize options, data_dir, configuration_file
      @quiet = if options[:quiet_given] then options[:quiet] else false end
      @dry_run = if options[:dry_run_given] then options[:dry_run] else false end

      @data_dir = data_dir

      load configuration_file
    end

    # Read a configuration file and create a pandocomatic configuration object
    #
    # @param [String] filename Path to the configuration yaml file
    # @returns [Configuration] a pandocomatic configuration object
    def load(filename)
      begin
        path = File.absolute_path filename
        settings = YAML.load_file path
        if settings['settings'] and settings['settings']['data-dir'] then
          data_dir = settings['settings']['data-dir']
          src_dir = File.dirname filename
          if data_dir.start_with? '.' then
            @data_dir = File.absolute_path data_dir, src_dir
          else
            @data_dir = data_dir
          end
        end
      rescue StandardError => e
        raise ConfigurationError.new(:unable_to_load_config_file, e, filename)
      end

      # hidden files will always be skipped, as will pandocomatic
      # configuration files, unless explicitly set to not skip via the
      # "unskip" option

      @settings = {'skip' => ['.*', 'pandocomatic.yaml']} 

      @templates = {}
      @convert_patterns = {}

      configure settings
    end

    # Update this configuration with a configuration file
    #
    # @param [String] filename path to the configuration file
    #
    # @returns [Configuration] a new configuration
    def reconfigure filename
      begin
        settings = YAML.load_file filename
        new_config = Marshal.load(Marshal.dump(self))
        new_config.configure settings
        new_config
      rescue StandardError => e
        raise ConfigurationError.new(:unable_to_load_config_file, e, filename)
      end
    end

    def configure settings
      reset_settings settings['settings'] if settings.has_key? 'settings'
      if settings.has_key? 'templates' then
        settings['templates'].each do |name, template|
          full_template = {
            'glob' => [],
            'preprocessors' => [],
            'pandoc' => {},
            'postprocessors' => []
          }

          reset_template name, full_template.merge(template)
        end
      end
    end

    def marshal_dump
      [@data_dir, @settings, @templates, @convert_patterns, @quiet, @dry_run]
    end

    def marshal_load(array)
      @data_dir, @settings, @templates, @convert_patterns, @quiet, @dry_run = array
    end

    def skip?(src)
      if @settings.has_key? 'skip' then
        @settings['skip'].any? {|glob| File.fnmatch glob, File.basename(src)}
      else
        false
      end
    end

    def quiet?
      @quiet
    end

    def dry_run?
      @dry_run
    end

    def convert?(src)
      @convert_patterns.values.flatten.any? {|glob| File.fnmatch glob, File.basename(src)}
    end

    def recursive?
      @settings['recursive']
    end

    def follow_links?
      @settings['follow_links']
    end

    def set_extension(dst)
      dir = File.dirname dst
      ext = File.extname dst
      basename = File.basename dst, ext
      File.join dir, "#{basename}.#{find_extension dst}"
    end

    def find_extension(dst)
      template = determine_template dst
      if template.nil? then
        extension = 'html'
      else
        # TODO: what if there is no pandoc.to?
        to = @templates[template]['pandoc']['to']
        extension = FORMAT_TO_EXT[to] || to
      end
    end

    def has_template?(template_name)
      @templates.has_key? template_name
    end

    def get_template(template_name)
      @templates[template_name]
    end

    def determine_template(src)
      @convert_patterns.select do |template_name, globs|
        globs.any? {|glob| File.fnmatch glob, File.basename(src)}
      end.keys.first
    end

    def update_path(path, src_dir)
      if path.start_with? './' 
        # refers to a local (to file) dir
        File.join src_dir, path
      elsif path.start_with? '/' then
        path
      else
        # refers to data-dir
        File.join @data_dir, path
      end
    end

    private 

    def reset_settings(settings)
      settings.each do |setting, value|
        case setting
        when 'skip'
          @settings['skip'] = @settings['skip'].concat(value).uniq
        when 'data-dir'
          next # skip data-dir setting; is set once in initialization
        else
          @settings[setting] = value
        end
      end
    end

    def reset_template(name, template)
      if @templates.has_key? name then
        fields = ['glob', 'preprocessors', 'pandoc', 'postprocessors']
        fields.each do |field|
          case field
          when 'preprocessors', 'postprocessors', 'glob'
            if @templates[name][field] then
              if template[field] then
                @templates[name][field].concat(template[field]).uniq!
              end
            else
              if template[field] then
                @templates[name][field] = template[field]
              end
            end
          when 'pandoc'
            if @templates[name][field] then
              if template[field] then
                @templates[name][field].merge! template[field]
              end
            else
              if template[field] then
                @templates[name][field] = template[field]
              end
            end
          end
        end
      else
        @templates[name] = template
      end

      if template.has_key? 'glob' then
        @convert_patterns[name] = template['glob']
      end
    end

  end

end
