# frozen_string_literal: true

require 'dspy'
require 'sorbet-runtime'

module ADEExample
  class ADETextClassifier < DSPy::Signature
    description 'Determine if a clinical sentence describes an adverse drug event (ADE)'

    class ADELabel < T::Enum
      enums do
        NotRelated = new('0')
        Related = new('1')
      end
    end

    input do
      const :text, String, description: 'Clinical sentence or patient report'
    end

    output do
      const :label, ADELabel, description: 'Whether the text is ADE-related'
    end
  end

  ExampleEvaluation = Struct.new(:accuracy, :precision, :recall, :f1)

  module_function

  def build_examples(rows)
    rows.map do |row|
      label = ADETextClassifier::ADELabel.deserialize(row.fetch('label', 0).to_s)
      DSPy::Example.new(
        signature_class: ADETextClassifier,
        input: { text: row.fetch('text', '') },
        expected: { label: label }
      )
    end
  end

  def split_examples(examples, train_ratio:, val_ratio:, seed: 42)
    return [[], [], []] if examples.empty?

    unless (train_ratio + val_ratio).between?(0.0, 1.0)
      raise ArgumentError, "train_ratio + val_ratio must be between 0 and 1"
    end

    random = Random.new(seed)
    train, val, test = default_split(examples.shuffle(random: random), train_ratio, val_ratio)

    label_groups = examples.group_by { |example| example.expected_values[:label] }
    if label_groups.size >= 2
      splits = { train: train, val: val, test: test }
      label_groups.keys.each do |label|
        ensure_label_presence!(splits, label)
      end

      random = Random.new(seed)
      train = splits[:train].shuffle(random: random)
      val = splits[:val].shuffle(random: random)
      test = splits[:test].shuffle(random: random)
    end

    [train, val, test]
  end

  def default_split(examples, train_ratio, val_ratio)
    train_size = (examples.size * train_ratio).round
    val_size = (examples.size * val_ratio).round

    train = examples.first(train_size)
    val = examples.slice(train_size, val_size) || []
    test = examples.drop(train_size + val_size)
    [train, val, test]
  end

  def ensure_label_presence!(splits, label)
    splits.each do |split_name, split_examples|
      next if split_examples.any? { |example| example.expected_values[:label] == label }

      donor_name, donor_split = splits
        .reject { |name, _| name == split_name }
        .select { |_, examples| examples.count { |example| example.expected_values[:label] == label } > 1 }
        .max_by { |_, examples| examples.count { |example| example.expected_values[:label] == label } }

      next unless donor_split

      donor_index = donor_split.index { |example| example.expected_values[:label] == label }
      next unless donor_index

      split_examples << donor_split.delete_at(donor_index)
    end
  end

  def label_from_prediction(prediction)
    value =
      if prediction.respond_to?(:label)
        prediction.label
      elsif prediction.is_a?(Hash)
        prediction[:label] || prediction['label']
      else
        prediction
      end

    return value if value.is_a?(ADETextClassifier::ADELabel)

    ADETextClassifier::ADELabel.deserialize(value.to_s)
  rescue StandardError
    nil
  end

  def evaluate(program, examples)
    return ExampleEvaluation.new(0.0, 0.0, 0.0, 0.0) if examples.empty?

    totals = {
      correct: 0,
      tp: 0,
      fp: 0,
      fn: 0
    }

    examples.each do |example|
      expected = example.expected_values[:label]
      prediction = program.call(**example.input_values)
      predicted = label_from_prediction(prediction)

      if predicted.nil?
        if expected == ADETextClassifier::ADELabel::Related
          totals[:fn] += 1
        else
          totals[:fp] += 1
        end
        next
      end

      totals[:correct] += 1 if predicted == expected

      if expected == ADETextClassifier::ADELabel::Related
        totals[:tp] += 1 if predicted == ADETextClassifier::ADELabel::Related
        totals[:fn] += 1 if predicted == ADETextClassifier::ADELabel::NotRelated
      elsif predicted == ADETextClassifier::ADELabel::Related
        totals[:fp] += 1
      end
    end

    accuracy = totals[:correct].to_f / examples.size
    precision = safe_divide(totals[:tp], totals[:tp] + totals[:fp])
    recall = safe_divide(totals[:tp], totals[:tp] + totals[:fn])
    f1 = safe_divide(2 * precision * recall, precision + recall)

    ExampleEvaluation.new(accuracy, precision, recall, f1)
  end

  def safe_divide(numerator, denominator)
    return 0.0 if denominator.nil? || denominator.zero?
    numerator.to_f / denominator
  end
end
