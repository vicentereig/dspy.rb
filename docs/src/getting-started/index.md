---
layout: docs
title: "Getting Started - Building Your First Reliable LLM System"
description: "Moving from unpredictable prompts to structured, testable applications"
section: getting-started
---

# Building Your First Reliable LLM System

*Moving from "crossing fingers" to "shipping with confidence"*

## The Problem Most Teams Face

If you've built LLM applications before, you've probably hit this wall: your demo works perfectly, but production is a nightmare of edge cases and unpredictable failures.

You're not alone. Most developers I work with are dealing with:
- Prompts that work in testing but fail with real user data
- Hours spent debugging string formatting instead of building features
- LLM responses that can't be parsed reliably
- No systematic way to test AI behavior

## What Actually Changes

DSPy.rb doesn't promise to revolutionize how you think about AI. It just gives you better tools for building LLM applications that work predictably.

Instead of treating LLMs as magic black boxes that respond to strings, you treat them as programmable modules with clear interfaces—just like any other part of your system.

Here's the shift:
- **Before**: Hope your prompt formatting works
- **After**: Define clear interfaces and let the system handle prompting

## Your First Structured Program

Let's see this in practice. Here's how most of us start:

```ruby
# The fragile approach
prompt = "You are a helpful assistant. Answer this question: #{user_question}"
response = llm.complete(prompt)
# Cross your fingers and hope it parses correctly...
```

Here's the same functionality, but structured:

```ruby
# Define what you want clearly
class QuestionAnswering < DSPy::Signature
  description "Answer questions accurately and concisely"
  
  input do
    const :question, String
  end
  
  output do
    const :answer, String, desc: "A clear, concise answer"
    const :confidence, Float, desc: "How confident are you? (0.0-1.0)"
  end
end

# Create a predictable system
qa_system = DSPy::Predict.new(QuestionAnswering)

# Use it reliably
result = qa_system.call(question: "What is the capital of France?")
puts result.answer      # "Paris"
puts result.confidence  # 0.95
```

## What You Just Gained

This isn't just different syntax—you solved several real problems:

1. **Clear Interface**: You defined exactly what goes in and what comes out
2. **Type Safety**: The system validates inputs and outputs automatically using Sorbet runtime types
3. **Structured Results**: No more parsing unpredictable response formats
4. **Systematic Testing**: You can write real tests for this behavior

Notice how the schema definitions use **idiomatic Ruby with Sorbet types**—no JSON schemas or configuration files needed. The `const` declarations create runtime type validation that integrates seamlessly with your existing Ruby codebase.

## Testing Your LLM System

Here's the part that changes everything—you can now test LLM behavior systematically:

```ruby
RSpec.describe QuestionAnswering do
  let(:qa_system) { DSPy::Predict.new(QuestionAnswering) }
  
  it "answers factual questions confidently" do
    result = qa_system.call(question: "What is 2 + 2?")
    
    expect(result.answer).to eq("4")
    expect(result.confidence).to be > 0.9
  end
  
  it "expresses uncertainty for ambiguous questions" do
    result = qa_system.call(question: "What's the best programming language?")
    
    expect(result.confidence).to be < 0.7
  end
end
```

No more manual testing. No more "hope it works in production." Just systematic verification like any other code.

## Common Questions

**"Isn't this just more complex prompting?"**

No—you're not writing prompts at all. DSPy.rb generates the prompts based on your signature. You focus on interface design instead of string manipulation.

**"Does this actually work with real LLMs?"**

Yes. Our test suite has 226+ specs running against real language models. The structured approach is more reliable than manual prompting, not less.

**"What about complex reasoning tasks?"**

That's where DSPy.rb really shines. You can chain reasoning steps, add tool usage, and build sophisticated workflows—all with the same structured approach.

## What You've Learned

In 10 minutes, you've:

- Moved from string manipulation to structured interfaces
- Gained the ability to test LLM behavior systematically  
- Built a foundation for more complex reasoning systems
- Eliminated most prompt engineering headaches

## Next Steps

This is just the foundation. From here you can:

### **🔧 Learn the Core Building Blocks**
**[Foundations →](/foundations/)**  
*Signatures, Predict, Chain of Thought, and ReAct modules*

### **🏗️ Build Multi-Step Systems**  
**[System Building →](/systems/)**  
*Chain reasoning steps into production workflows*

### **🤖 Add Tool Usage**
**[Agent Patterns →](/collaboration/)**  
*Build LLMs that interact with external systems*

## The Engineering Reality

Building reliable LLM applications isn't about philosophical transformation—it's about applying good engineering practices to a new type of system.

DSPy.rb gives you the tools. The rest is just software engineering.

**Ready to build something that actually works?**

---

*"LLM applications are just software. They should be built like software."*
