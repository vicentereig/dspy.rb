---
layout: default
title: "DSPy.rb - Build Reliable LLM Applications in Ruby"
description: "A framework for building predictable LLM applications using composable, type-safe modules"
---

# Building LLM Applications That Actually Work

*A practical approach to reliable AI programming*

## The Real Problem

Most developers I meet are stuck in the same place: their LLM applications work great in demos but fail unpredictably in production.

You've probably been there—spending more time debugging prompt edge cases than building features, watching systems that worked perfectly in testing break mysteriously when real users touch them.

## What DSPy.rb Actually Does

DSPy.rb doesn't promise to revolutionize how you think about AI. It just gives you tools to build LLM applications that behave predictably:

- **Type-safe interfaces** instead of string manipulation
- **Composable modules** instead of monolithic prompts
- **Systematic testing** instead of trial-and-error debugging
- **Clear error handling** instead of mysterious failures

It's not magic. It's just better engineering.

## Where Most Developers Are

Based on working with teams building LLM applications, most developers fall into these categories:

**🔧 The String Wrangler**
- Everything is prompt engineering
- Debugging means staring at logs
- Success feels random

**📝 The Template Builder** 
- Some structure with string templates
- Still fragile with edge cases
- Hard to test systematically

**🏗️ The Framework User** *(most teams)*
- Using AI libraries without understanding internals
- Copy-pasting examples from docs
- Unpredictable system behavior

**⚙️ The Systems Builder** *(where DSPy.rb helps you get)*
- Building from composable, tested modules
- Predictable system behavior
- Reliable production deployments

**🏢 The Production Engineer** *(the goal)*
- Systems that monitor and improve themselves
- Clear patterns for common problems
- Confidence in AI system behavior

Which category describes your current experience?

## How to Get Started

### **🚀 Stop Fighting String Formatting**

**[Getting Started →](/getting-started/)**  
*Your first structured LLM program in 10 minutes*

See how type-safe signatures eliminate most prompt engineering headaches.

### **🔧 Learn the Core Patterns**

**[Foundations →](/foundations/)**  
*The building blocks that actually work in production*

Understand Signatures, Predict, Chain of Thought, and ReAct—the modules that make LLM applications reliable.

### **🏗️ Build Production Systems**

**[System Building →](/systems/)**  
*From proof-of-concept to production-ready*

Learn to chain reasoning steps, handle errors gracefully, and test LLM systems like any other code.

### **🤖 Use AI Tools Effectively**

**[Agent Patterns →](/collaboration/)**  
*When LLMs need to interact with the real world*

Build agents that use tools reliably, not just when they feel like it.

## Why Ruby for LLM Applications?

Python dominates AI development, but Ruby brings unique advantages:

- **Clear, readable code** - LLM logic stays understandable
- **Idiomatic Sorbet types** - Define schemas in Ruby, not JSON or YAML configs
- **Runtime type validation** - Catch interface errors before they hit production  
- **Mature testing culture** - Our 226+ specs prove everything works
- **Production-ready ecosystem** - Rails, Sidekiq, etc. for real applications

Here's what makes DSPy.rb different—**everything is just Ruby**:

```ruby
# Define LLM interfaces using familiar Ruby syntax
class EmailClassifier < DSPy::Signature
  input do
    const :subject, String
    const :body, String
    const :priority, T.nilable(Symbol), enum: [:low, :high], default: :low
  end
  
  output do
    const :category, String, enum: ["billing", "technical", "general"]
    const :confidence, Float
    const :suggested_actions, T::Array[String]
  end
end

# ReAct tools also use Ruby types
class DatabaseQuery < DSPy::Tool
  input do
    const :query, String
    const :limit, T.nilable(Integer), default: 10
  end
  
  output do
    const :results, T::Array[T::Hash[String, T.untyped]]
    const :execution_time_ms, Float
  end
end
```

No external schema languages. No configuration files. Just Ruby code that's statically analyzed by Sorbet and validated at runtime.

More importantly: Ruby's focus on developer productivity extends naturally to building reliable LLM applications.

## Real Engineering, Not Magic

This documentation focuses on practical engineering:

- **Working examples** from our comprehensive test suite
- **Common failure patterns** and how to avoid them
- **Production debugging** when things go wrong
- **Performance considerations** that actually matter

The goal isn't philosophical transformation—it's building LLM applications you can actually deploy with confidence.

## The Community

Building reliable LLM applications is still a new problem space:

- **📚 [Learn from Real Examples](/practice/)** - Case studies and production stories
- **🛠️ [Contribute](https://github.com/vicentereig/dspy.rb)** - Help solve common problems
- **💬 [Discuss](https://github.com/vicentereig/dspy.rb/discussions)** - Share what you've learned

## Ready to Start?

The main question isn't "How do I use DSPy.rb?" but **"How do I build LLM applications that actually work in production?"**

Start with the problems you're currently facing. Notice where your current approach breaks down. Focus on building systems you can actually trust.

**[Start Building →](/getting-started/)**

---

*"LLM applications don't need to be unreliable. They just need better engineering."*
