---
layout: docs
title: Packages and capabilities
description: Choose DSPy.rb gems without confusing package availability with provider or model support.
date: 2026-07-14 00:00:00 +0000
last_modified_at: 2026-07-15 00:00:00 +0000
---
{% assign matrix = site.data.package_capabilities %}
# Packages and capabilities

Start with `dspy`, then add the package that owns the provider or optional feature you use. A gem's presence means its Ruby entry point is available. It does not mean every model or provider endpoint implements every capability.

The table below is generated from [`package_capabilities.yml`](https://github.com/vicentereig/dspy.rb/blob/main/docs/src/_data/package_capabilities.yml), the canonical package inventory.

## Status labels

{% for status in matrix.support_statuses %}
- **{{ status[0] }}** — {{ status[1] }}
{% endfor %}

These labels describe this repository's documentation and test posture. They do not extend the compatibility promises made by provider APIs or third-party SDKs.

## Package matrix

| Install package | Role | Status | Require path | Detailed guide |
| --- | --- | --- | --- | --- |
{% for package in matrix.packages %}{% if package.visibility == 'public' %}| `{{ package.gem }}` | {{ package.role }} | {{ package.support_status }} | `{{ package.require_path }}` | {% if package.guide contains 'repository:' %}[repository guide](https://github.com/vicentereig/dspy.rb/blob/main/{{ package.guide | remove: 'repository:' }}){% else %}[guide](/dspy.rb{{ package.guide }}){% endif %} |
{% endif %}
{% endfor %}

{% for package in matrix.packages %}
{% if package.visibility == 'public' %}
### `{{ package.gem }}`

- **Install:** `{{ package.install }}`
- **Loading:** {{ package.load_behavior }}
- **Provides:** {{ package.capabilities }}
- **Boundary:** {{ package.limitations }}
{% if package.monorepo_flag %}
**Monorepo development only:** `{{ package.monorepo_flag }}=1` selects this repository's local gemspec. Application users install the gem instead.
{% endif %}
{% endif %}
{% endfor %}

## Current gem file overlaps

These are packaging facts, not separate implementations. The validator compares every tracked gemspec pair and fails if this list drifts.

{% for overlap in matrix.declared_file_overlaps %}
{% assign left_package = matrix.packages | where: "gem", overlap.packages[0] | first %}
{% assign right_package = matrix.packages | where: "gem", overlap.packages[1] | first %}
{% if left_package.visibility == "public" and right_package.visibility == "public" %}
- **`{{ overlap.packages[0] }}` + `{{ overlap.packages[1] }}`:** {{ overlap.disclosure }} Overlapping files: {% for path in overlap.paths %}`{{ path }}`{% unless forloop.last %}, {% endunless %}{% endfor %}.
{% endif %}
{% endfor %}

## Provider capability boundary

- **Availability:** {{ matrix.provider_policy.availability }}
- **Capability:** {{ matrix.provider_policy.capability }}
- **Verification:** {{ matrix.provider_policy.verification }}

RubyLLM is deliberately one row, not a promise that all of its underlying providers behave alike. Its registry and SDK determine model discovery; DSPy.rb still applies narrower boundaries where the adapter has them. For example, document inputs through RubyLLM currently require an Anthropic model.

## Renamed packages

{% for legacy in matrix.legacy_names %}
- Do not install `{{ legacy.name }}`. Use `{{ legacy.replacement }}`.
{% endfor %}

## CodeAct safety boundary

`dspy-code_act` executes model-generated Ruby with the process's authority. Installing it does not add a sandbox, resource isolation, a permission system, or safe handling for untrusted input. Put execution behind an isolation boundary appropriate to the data and side effects involved; the application owns that boundary.

## Monorepo flags are not application configuration

{{ matrix.monorepo_flags.policy }} Packages without a flag are not selected by a `DSPY_WITH_*` switch.
