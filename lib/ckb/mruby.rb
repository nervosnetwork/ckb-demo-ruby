module Ckb
  module Mruby
    def self.out_point
      raise "Mruby cell configuration not setup!" unless @out_point
      @out_point
    end

    def self.cell_hash
      raise "Mruby cell configuration not setup!" unless @cell_hash
      @cell_hash
    end

    def self.load_configuration!(configuration_filename)
      set_configuration!(JSON.parse(File.read(configuration_filename), symbolize_names: true))
    end

    def self.save_configuration!(configuration_filename)
      conf = {
        out_point: out_point,
        cell_hash: cell_hash
      }
      File.write(configuration_filename, conf.to_json)
    end

    def self.set_configuration!(configuration)
      @out_point = configuration[:out_point]
      @cell_hash = configuration[:cell_hash]
    end
  end
end
