# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'gepa'

RSpec.describe GEPA::Logging::Logger do
  it 'writes messages to the provided IO' do
    io = StringIO.new
    logger = described_class.new(io: io)

    logger.log('hello world')

    expect(io.string).to eq("hello world\n")
  end
end

RSpec.describe GEPA::Logging::CompositeLogger do
  it 'fans out messages to all targets' do
    first = StringIO.new
    second = StringIO.new
    logger = described_class.new(first, second)

    logger.log('payload')

    expect(first.string).to eq("payload\n")
    expect(second.string).to eq("payload\n")
  end
end

RSpec.describe GEPA::Logging::BufferingLogger do
  it 'stores messages in memory' do
    logger = described_class.new
    logger.log('one')
    logger.log('two')

    expect(logger.messages).to eq(%w[one two])
  end
end

