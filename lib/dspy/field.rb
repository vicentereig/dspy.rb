# frozen_string_literal: true

module DSPy
  class InputField
    attr_reader :name, :type, :desc
    
    def initialize(name, type, desc: nil)
      @name = name
      @type = type
      @desc = desc
    end
  end
  
  class OutputField
    attr_reader :name, :type, :desc
    
    def initialize(name, type, desc: nil)
      @name = name
      @type = type
      @desc = desc
    end
  end
end 