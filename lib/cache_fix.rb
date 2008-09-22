# Because Rails' FileStore doesn't Marshal data
if Rails.version == '2.1.0'

  module ActiveSupport
    module Cache
      class FileStore < Store
        attr_reader :cache_path

        def read(name, options = nil)
          super
          File.open(real_file_path(name), 'rb') { |f| Marshal.load(f) } rescue nil
        end

        def write(name, value, options = nil)
          super
          ensure_cache_path(File.dirname(real_file_path(name)))
          File.atomic_write(real_file_path(name), cache_path) { |f| Marshal.dump(value, f) }
        rescue => e
          logger.error "Couldn't create cache directory: #{name} (#{e.message})" if logger
        end
      
      end
    end
  end

end