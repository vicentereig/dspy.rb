---
layout: blog
title: "Saving Optimized DSPy.rb Programs"
description: "Use Module#save or ProgramStorage to persist serializable program state and optimization metadata."
date: 2025-08-26
author: "Vicente Reig"
category: "Features"
reading_time: "4 min read"
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/program-persistence-and-serialization/"
image: /images/og/program-persistence-and-serialization.png
---

An optimizer can spend minutes, provider tokens, and a fair amount of patience finding better instructions and demonstrations. DSPy.rb v0.20.0 added storage primitives so applications do not have to discard that work.

There are two APIs. They solve different problems.

## Save Module State to JSON

Every `DSPy::Module` has `save(path)`. It writes the module's `to_h` result as formatted JSON and creates the parent directory when needed.

```ruby
program.save("artifacts/support_classifier.json")
```

The base implementation only records the class name and an empty state:

```ruby
{
  class_name: "SupportClassifier",
  state: {}
}
```

Useful persistence therefore depends on the module. Built-in modules can override `to_h`; custom modules should serialize the state required to reproduce their behavior.

`Module#save` does not provide a corresponding universal `Module.load`. Ruby cannot safely reconstruct an arbitrary object graph from a class name. Treat the file as a state artifact and implement an explicit loader for your module when you need one.

## Store Optimization Results

`DSPy::Storage::ProgramStorage` keeps program state, optimization metadata, and a history index:

```ruby
require "dspy/storage/program_storage"

storage = DSPy::Storage::ProgramStorage.new(
  storage_path: "./dspy_storage"
)

saved = storage.save_program(
  optimized_program,
  optimization_result,
  metadata: {
    dataset: "support-v2",
    git_sha: ENV["GIT_SHA"]
  }
)

puts saved.program_id
```

The storage directory contains one JSON file per program under `programs/` and a `history.json` index. `list_programs` and `get_history` read that index.

```ruby
storage.list_programs.each do |entry|
  puts [entry[:program_id], entry[:best_score], entry[:saved_at]].join("\t")
end
```

## Loading a Program

```ruby
loaded = storage.load_program(saved.program_id)

if loaded
  program = loaded.program
  result = loaded.optimization_result
  metadata = loaded.metadata
end
```

Loading is deliberately constrained. The stored `class_name` must resolve to a loaded Ruby constant, and that class must implement `.from_h`.

`ProgramStorage` does not call an arbitrary module's `to_h`. Its current serializer extracts a small common state: the signature class name, prompt instruction, and few-shot examples when the program exposes them. Built-in program classes that implement compatible `.from_h` methods can reconstruct that state. A custom module with additional instance state needs its own persistence boundary; `Module#save` plus an explicit loader is the clearer option.

Persist model identifiers, instructions, demonstrations, and configuration that affect behavior. Do not serialize credentials.

`load_program` returns `nil` when the file is absent or deserialization fails. If an application must distinguish those cases, validate the artifact and class compatibility before deployment rather than relying on a late load.

## Export, Import, and Deletion

Program storage can move selected artifacts between files and remove old entries:

```ruby
storage.export_programs([saved.program_id], "release/programs.json")
storage.import_programs("release/programs.json")
storage.delete_program(saved.program_id)
```

An export is JSON, not a self-contained Ruby package. The destination still needs the same program class and compatible `.from_h` behavior.

## Storage Manager

`DSPy::Storage::StorageManager` wraps `ProgramStorage` for optimizer results. It can auto-save an `optimized_program`, find saved programs by score, age, tags, optimizer, or signature class, and retain a configured number of artifacts.

```ruby
require "dspy/storage/storage_manager"

config = DSPy::Storage::StorageManager::StorageConfig.new
config.storage_path = "./dspy_storage"
config.max_stored_programs = 25

manager = DSPy::Storage::StorageManager.new(config: config)
manager.save_optimization_result(
  optimization_result,
  tags: ["support", "candidate"],
  description: "GEPA run on support-v2"
)
```

This is filesystem storage with a JSON history file. It has no locking or transactional database behind it. Coordinate writers yourself, and use object storage or a database when several processes must publish artifacts concurrently.

## What to Version

A saved prompt artifact is only one part of an LM program. Record enough context to explain a result later:

- DSPy.rb and Ruby versions
- model identifier and provider configuration
- optimizer and metric
- dataset or fixture version
- application commit
- custom module serialization version

`ProgramStorage` records DSPy.rb and Ruby versions automatically. The application must supply the rest as metadata.

Evaluate an artifact before promoting it, and evaluate the loaded artifact again to catch incompatible code or serialization changes.
