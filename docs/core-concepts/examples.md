# Examples & Validation

Examples are type-safe training data objects that enable systematic optimization and evaluation of your DSPy modules. They provide the foundation for automated prompt optimization and performance measurement.

## Creating Basic Examples

```ruby
class ClassifyText < DSPy::Signature
  description "Classify text sentiment and confidence"
  
  class Sentiment < T::Enum
    enums do
      Positive = new('positive')
      Negative = new('negative')
      Neutral = new('neutral')
    end
  end
  
  input do
    const :text, String
  end
  
  output do
    const :sentiment, Sentiment
    const :confidence, Float
  end
end

# Create examples with known correct outputs
examples = [
  DSPy::Example.new(
    inputs: { text: "I absolutely love this product!" },
    outputs: { 
      sentiment: ClassifyText::Sentiment::Positive, 
      confidence: 0.95 
    }
  ),
  DSPy::Example.new(
    inputs: { text: "This is the worst experience ever." },
    outputs: { 
      sentiment: ClassifyText::Sentiment::Negative, 
      confidence: 0.92 
    }
  ),
  DSPy::Example.new(
    inputs: { text: "The weather is okay today." },
    outputs: { 
      sentiment: ClassifyText::Sentiment::Neutral, 
      confidence: 0.78 
    }
  )
]
```

## Type Safety and Validation

Examples are automatically validated against your signature's type constraints:

```ruby
# This will raise a validation error
invalid_example = DSPy::Example.new(
  inputs: { text: "Sample text" },
  outputs: { 
    sentiment: "positive",  # String instead of Sentiment enum - ERROR!
    confidence: 1.5         # > 1.0 - might be invalid depending on validation
  }
)
# => DSPy::ValidationError: Expected ClassifyText::Sentiment, got String
```

### Custom Validation Rules

```ruby
class ProductReview < DSPy::Signature
  description "Analyze product reviews with custom validation"
  
  input do
    const :review, String
    const :product_category, String
  end
  
  output do
    const :rating, Integer
    const :aspects, T::Hash[String, Integer]
    const :recommendation, String
  end
  
  # Custom validation method
  def self.validate_example(example)
    output = example.outputs
    
    # Rating must be 1-5
    unless (1..5).include?(output[:rating])
      raise DSPy::ValidationError, "Rating must be between 1 and 5"
    end
    
    # All aspect ratings must be 1-5
    output[:aspects].each do |aspect, rating|
      unless (1..5).include?(rating)
        raise DSPy::ValidationError, "Aspect rating for '#{aspect}' must be between 1 and 5"
      end
    end
    
    # Recommendation length check
    if output[:recommendation].length < 10
      raise DSPy::ValidationError, "Recommendation must be at least 10 characters"
    end
  end
end

# Valid example
valid_example = DSPy::Example.new(
  inputs: { 
    review: "Great phone with excellent camera quality.",
    product_category: "electronics"
  },
  outputs: { 
    rating: 4,
    aspects: { "camera" => 5, "battery" => 3, "design" => 4 },
    recommendation: "Recommended for photography enthusiasts."
  }
)
```

## Example Collections

### Organizing Examples by Category

```ruby
class ExampleCollection
  def initialize
    @examples = []
    @categories = {}
  end
  
  def add_example(example, category: :default)
    @examples << example
    @categories[category] ||= []
    @categories[category] << example
  end
  
  def examples_for_category(category)
    @categories[category] || []
  end
  
  def train_test_split(ratio: 0.8)
    shuffled = @examples.shuffle
    split_index = (shuffled.size * ratio).to_i
    
    {
      train: shuffled[0...split_index],
      test: shuffled[split_index..-1]
    }
  end
end

# Usage
collection = ExampleCollection.new

# Add categorized examples
collection.add_example(positive_example, category: :positive)
collection.add_example(negative_example, category: :negative)
collection.add_example(neutral_example, category: :neutral)

# Get balanced training set
train_data = [:positive, :negative, :neutral].flat_map do |category|
  collection.examples_for_category(category).sample(10)  # 10 examples each
end
```

### Loading Examples from Data Sources

```ruby
class ExampleLoader
  def self.from_csv(file_path, signature_class)
    examples = []
    
    CSV.foreach(file_path, headers: true) do |row|
      # Parse inputs
      inputs = parse_inputs(row, signature_class)
      
      # Parse outputs  
      outputs = parse_outputs(row, signature_class)
      
      examples << DSPy::Example.new(inputs: inputs, outputs: outputs)
    end
    
    examples
  end
  
  def self.from_json(file_path, signature_class)
    data = JSON.parse(File.read(file_path))
    
    data.map do |item|
      DSPy::Example.new(
        inputs: item['inputs'],
        outputs: parse_json_outputs(item['outputs'], signature_class)
      )
    end
  end
  
  private
  
  def self.parse_outputs(row, signature_class)
    outputs = {}
    
    signature_class.output_fields.each do |field_name, field_type|
      value = row[field_name.to_s]
      outputs[field_name] = coerce_type(value, field_type)
    end
    
    outputs
  end
  
  def self.coerce_type(value, type)
    case type
    when Class
      if type < T::Enum
        type.deserialize(value)
      else
        type.new(value)
      end
    when Float
      value.to_f
    when Integer
      value.to_i
    when T::Boolean
      value.to_s.downcase == 'true'
    else
      value
    end
  end
end

# Load examples from CSV
examples = ExampleLoader.from_csv('data/sentiment_examples.csv', ClassifyText)

# Load examples from JSON
examples = ExampleLoader.from_json('data/sentiment_examples.json', ClassifyText)
```

## Few-Shot Examples

Examples can be used to provide few-shot context to improve model performance:

```ruby
class FewShotPredictor
  def initialize(signature, examples: [])
    @signature = signature
    @base_predictor = DSPy::Predict.new(signature)
    @examples = examples
  end
  
  def call(inputs)
    # Create few-shot context from examples
    few_shot_context = build_few_shot_context(@examples)
    
    # Add context to the prediction
    @base_predictor.call(inputs.merge(examples: few_shot_context))
  end
  
  private
  
  def build_few_shot_context(examples)
    examples.map do |example|
      "Input: #{example.inputs.values.join(' ')}\n" \
      "Output: #{format_outputs(example.outputs)}"
    end.join("\n\n")
  end
  
  def format_outputs(outputs)
    outputs.map { |k, v| "#{k}: #{v}" }.join(", ")
  end
end

# Usage with few-shot examples
few_shot_classifier = FewShotPredictor.new(
  ClassifyText,
  examples: [positive_example, negative_example, neutral_example]
)

result = few_shot_classifier.call(text: "This movie was incredible!")
```

## Example Generation

### Automatic Example Generation

```ruby
class ExampleGenerator
  def initialize(signature, generator_lm: nil)
    @signature = signature
    @generator = DSPy::Predict.new(GenerateExamples)
    @generator_lm = generator_lm || DSPy.config.lm
  end
  
  def generate_examples(count: 10, category: nil)
    examples = []
    
    count.times do
      generated = @generator.call(
        signature_description: @signature.description,
        input_fields: @signature.input_fields.keys.join(", "),
        output_fields: @signature.output_fields.keys.join(", "),
        category: category
      )
      
      # Parse and validate generated example
      example = parse_generated_example(generated)
      examples << example if valid_example?(example)
    end
    
    examples
  end
  
  private
  
  def parse_generated_example(generated)
    # Parse the LLM's generated example into DSPy::Example format
    inputs = parse_generated_inputs(generated.inputs)
    outputs = parse_generated_outputs(generated.outputs)
    
    DSPy::Example.new(inputs: inputs, outputs: outputs)
  rescue StandardError => e
    Rails.logger.warn "Failed to parse generated example: #{e.message}"
    nil
  end
  
  def valid_example?(example)
    return false if example.nil?
    
    @signature.validate_example(example)
    true
  rescue DSPy::ValidationError
    false
  end
end

class GenerateExamples < DSPy::Signature
  description "Generate realistic examples for a given signature"
  
  input do
    const :signature_description, String
    const :input_fields, String
    const :output_fields, String
    const :category, T.nilable(String)
  end
  
  output do
    const :inputs, T::Hash[String, T.untyped]
    const :outputs, T::Hash[String, T.untyped]
    const :reasoning, String
  end
end

# Generate examples automatically
generator = ExampleGenerator.new(ClassifyText)
generated_examples = generator.generate_examples(count: 20, category: "product_reviews")
```

### Data Augmentation

```ruby
class ExampleAugmenter
  def initialize(signature)
    @signature = signature
    @paraphraser = DSPy::Predict.new(ParaphraseText)
    @back_translator = DSPy::ChainOfThought.new(BackTranslate)
  end
  
  def augment_examples(examples, multiplier: 2)
    augmented = examples.dup
    
    examples.each do |original|
      (multiplier - 1).times do
        augmented << augment_single_example(original)
      end
    end
    
    augmented
  end
  
  private
  
  def augment_single_example(example)
    method = [:paraphrase, :back_translate].sample
    
    case method
    when :paraphrase
      augment_by_paraphrasing(example)
    when :back_translate
      augment_by_back_translation(example)
    end
  end
  
  def augment_by_paraphrasing(example)
    # Paraphrase input text while keeping outputs the same
    text_inputs = example.inputs.select { |k, v| v.is_a?(String) }
    
    paraphrased_inputs = example.inputs.dup
    text_inputs.each do |key, text|
      paraphrased = @paraphraser.call(text: text)
      paraphrased_inputs[key] = paraphrased.paraphrased_text
    end
    
    DSPy::Example.new(
      inputs: paraphrased_inputs,
      outputs: example.outputs  # Keep original outputs
    )
  end
  
  def augment_by_back_translation(example)
    # Back-translate through another language
    text_inputs = example.inputs.select { |k, v| v.is_a?(String) }
    
    back_translated_inputs = example.inputs.dup
    text_inputs.each do |key, text|
      back_translated = @back_translator.call(
        text: text,
        intermediate_language: ['es', 'fr', 'de'].sample
      )
      back_translated_inputs[key] = back_translated.back_translated_text
    end
    
    DSPy::Example.new(
      inputs: back_translated_inputs,
      outputs: example.outputs
    )
  end
end
```

## Example Quality Assessment

### Automatic Quality Scoring

```ruby
class ExampleQualityAssessor
  def initialize(signature)
    @signature = signature
    @quality_checker = DSPy::ChainOfThought.new(AssessExampleQuality)
  end
  
  def assess_examples(examples)
    examples.map do |example|
      quality_score = assess_single_example(example)
      
      {
        example: example,
        quality_score: quality_score.score,
        quality_issues: quality_score.issues,
        recommendations: quality_score.recommendations
      }
    end
  end
  
  def filter_high_quality(examples, threshold: 0.8)
    assessed = assess_examples(examples)
    
    assessed.select { |item| item[:quality_score] >= threshold }
            .map { |item| item[:example] }
  end
  
  private
  
  def assess_single_example(example)
    @quality_checker.call(
      signature_description: @signature.description,
      example_inputs: example.inputs.to_json,
      example_outputs: example.outputs.to_json,
      input_constraints: get_input_constraints,
      output_constraints: get_output_constraints
    )
  end
end

class AssessExampleQuality < DSPy::Signature
  description "Assess the quality of a training example for a given signature"
  
  input do
    const :signature_description, String
    const :example_inputs, String
    const :example_outputs, String
    const :input_constraints, String
    const :output_constraints, String
  end
  
  output do
    const :score, Float                    # 0.0 to 1.0
    const :issues, T::Array[String]        # List of quality issues
    const :recommendations, T::Array[String] # How to improve
  end
end
```

### Diversity Analysis

```ruby
class ExampleDiversityAnalyzer
  def initialize(signature)
    @signature = signature
    @similarity_checker = DSPy::Predict.new(CheckSimilarity)
  end
  
  def analyze_diversity(examples)
    similarity_matrix = build_similarity_matrix(examples)
    
    {
      average_similarity: calculate_average_similarity(similarity_matrix),
      diversity_score: 1.0 - calculate_average_similarity(similarity_matrix),
      clusters: identify_clusters(examples, similarity_matrix),
      recommendations: generate_diversity_recommendations(examples, similarity_matrix)
    }
  end
  
  def identify_underrepresented_cases(examples)
    # Analyze output distribution
    output_distribution = analyze_output_distribution(examples)
    
    # Find rare cases
    rare_cases = output_distribution.select { |output, count| count < 3 }
    
    {
      rare_outputs: rare_cases.keys,
      distribution: output_distribution,
      balance_score: calculate_balance_score(output_distribution)
    }
  end
  
  private
  
  def build_similarity_matrix(examples)
    matrix = Array.new(examples.size) { Array.new(examples.size, 0.0) }
    
    examples.each_with_index do |example1, i|
      examples.each_with_index do |example2, j|
        next if i >= j
        
        similarity = calculate_similarity(example1, example2)
        matrix[i][j] = matrix[j][i] = similarity
      end
    end
    
    matrix
  end
  
  def calculate_similarity(example1, example2)
    # Compare inputs using semantic similarity
    input_similarity = @similarity_checker.call(
      text1: example1.inputs.values.join(" "),
      text2: example2.inputs.values.join(" ")
    ).similarity_score
    
    # Compare outputs for exact matches
    output_similarity = example1.outputs == example2.outputs ? 1.0 : 0.0
    
    # Weighted combination
    (input_similarity * 0.7) + (output_similarity * 0.3)
  end
end
```

## Example Testing

### Validation Testing

```ruby
RSpec.describe DSPy::Example do
  let(:signature) { ClassifyText }
  
  describe "validation" do
    it "accepts valid examples" do
      example = DSPy::Example.new(
        inputs: { text: "Sample text" },
        outputs: { 
          sentiment: ClassifyText::Sentiment::Positive,
          confidence: 0.8
        }
      )
      
      expect { signature.validate_example(example) }.not_to raise_error
    end
    
    it "rejects invalid output types" do
      example = DSPy::Example.new(
        inputs: { text: "Sample text" },
        outputs: { 
          sentiment: "positive",  # Should be enum
          confidence: 0.8
        }
      )
      
      expect { signature.validate_example(example) }.to raise_error(DSPy::ValidationError)
    end
  end
end
```

### Performance Testing

```ruby
RSpec.describe "Example Performance" do
  let(:examples) { load_test_examples }
  let(:predictor) { DSPy::Predict.new(ClassifyText) }
  
  it "achieves expected accuracy on examples" do
    correct_predictions = 0
    
    examples.each do |example|
      result = predictor.call(example.inputs)
      correct_predictions += 1 if result.sentiment == example.outputs[:sentiment]
    end
    
    accuracy = correct_predictions.to_f / examples.size
    expect(accuracy).to be >= 0.8  # Expect 80% accuracy
  end
end
```

## Best Practices

### 1. Balanced Examples

```ruby
# Ensure balanced representation across all output categories
def create_balanced_examples
  categories = ClassifyText::Sentiment.values
  examples_per_category = 20
  
  categories.flat_map do |sentiment|
    generate_examples_for_sentiment(sentiment, count: examples_per_category)
  end
end
```

### 2. Edge Case Coverage

```ruby
# Include edge cases and boundary conditions
edge_case_examples = [
  # Empty/minimal text
  DSPy::Example.new(
    inputs: { text: "Ok." },
    outputs: { sentiment: ClassifyText::Sentiment::Neutral, confidence: 0.6 }
  ),
  
  # Mixed sentiment
  DSPy::Example.new(
    inputs: { text: "I love the product but hate the price." },
    outputs: { sentiment: ClassifyText::Sentiment::Neutral, confidence: 0.7 }
  ),
  
  # Sarcasm
  DSPy::Example.new(
    inputs: { text: "Oh great, another broken feature." },
    outputs: { sentiment: ClassifyText::Sentiment::Negative, confidence: 0.8 }
  )
]
```

### 3. Regular Quality Assessment

```ruby
def maintain_example_quality(examples)
  assessor = ExampleQualityAssessor.new(ClassifyText)
  
  # Regular quality checks
  quality_report = assessor.assess_examples(examples)
  
  # Remove low-quality examples
  high_quality = assessor.filter_high_quality(examples, threshold: 0.7)
  
  # Generate new examples if needed
  if high_quality.size < minimum_example_count
    generator = ExampleGenerator.new(ClassifyText)
    additional = generator.generate_examples(count: minimum_example_count - high_quality.size)
    high_quality.concat(additional)
  end
  
  high_quality
end
```

### 4. Version Control for Examples

```ruby
class ExampleVersionControl
  def initialize(storage_path)
    @storage_path = storage_path
  end
  
  def save_examples(examples, version:, metadata: {})
    version_data = {
      version: version,
      created_at: Time.current,
      examples: examples.map(&:to_h),
      metadata: metadata,
      checksum: calculate_checksum(examples)
    }
    
    File.write("#{@storage_path}/examples_v#{version}.json", version_data.to_json)
  end
  
  def load_examples(version:)
    data = JSON.parse(File.read("#{@storage_path}/examples_v#{version}.json"))
    
    data['examples'].map do |example_data|
      DSPy::Example.new(
        inputs: example_data['inputs'],
        outputs: example_data['outputs']
      )
    end
  end
end
```

Examples are the foundation of DSPy optimization. Well-crafted, diverse, and high-quality examples enable automatic prompt optimization and reliable performance measurement. Invest time in creating and maintaining excellent example datasets for best results.