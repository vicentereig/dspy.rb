---
layout: blog
title: "LLM-as-a-Judge: Evaluating AI SDR Quality Beyond Simple Rules"
date: 2025-09-09
description: "Define and calibrate an LLM judge for prospect relevance, personalization, professional tone, and sales-email review."
author: "Vicente Reig"
tags: ["evaluation", "llm-judge", "sales", "sdr", "custom-metrics"]
canonical_url: "https://oss.vicente.services/dspy.rb/blog/articles/llm-as-judge-ai-sdr-evaluation/"
image: /images/og/llm-as-judge-ai-sdr-evaluation.png
---

You've built a program that finds prospects and writes sales emails. Before it sends anything, you need a definition of acceptable output.

Some requirements are deterministic: an address is present, an unsubscribe mechanism exists, or a claim appears in approved source data. Other judgments are harder to encode as rules: whether the prospect fits the campaign, whether personalization is supported by evidence, and whether the email sounds credible.

An LLM judge can score those qualitative dimensions. It should complement deterministic checks and human review, not replace either one.

## What Rules Can And Cannot Tell You

A keyword metric can detect whether an email mentions a name or company:

```ruby
def evaluate_personalization(email, prospect)
  score = 0.0
  score += 0.2 if email.include?(prospect.first_name)
  score += 0.3 if email.include?(prospect.company)
  score += 0.5 if email.match?(/recent|news|announcement/i)
  score
end
```

It cannot establish that the reference is accurate or naturally connected to the offer. An LLM judge can inspect that context, but its answer is still a model prediction. It can vary between runs, inherit model biases, or confidently approve unsupported claims.

Engagement metrics answer a different question:

```ruby
def evaluate_campaign_performance(campaign)
  {
    open_rate: campaign.opens.count.to_f / campaign.sends.count,
    reply_rate: campaign.replies.count.to_f / campaign.sends.count,
    positive_reply_rate: campaign.positive_replies.count.to_f / campaign.replies.count
  }
end
```

Those measurements arrive after sending and are affected by deliverability, targeting, timing, and the offer itself. They are useful outcome evidence, but they do not make a pre-send judge correct.

## Give The Judge Structured Evidence

The judge needs the targeting criteria, the selected prospect, the generated email, and the sender's approved context. `T::Struct` makes those boundaries visible.

```ruby
class TargetCriteria < T::Struct
  const :role, String
  const :company, String
  const :industry, String
  const :seniority_level, T.nilable(String)
  const :department, T.nilable(String)
end

class ProspectProfile < T::Struct
  const :first_name, String
  const :last_name, String
  const :title, String
  const :company, String
  const :industry, String
  const :linkedin_url, T.nilable(String)
  const :company_size, T.nilable(String)
end

class EmailCampaign < T::Struct
  const :subject, String
  const :body, String
  const :sender_name, String
  const :sender_email, String
  const :signature, T.nilable(String)
end

class SenderContext < T::Struct
  const :company, String
  const :value_proposition, String
  const :industry_focus, T.nilable(String)
  const :case_studies, T.nilable(T::Array[String])
end
```

The output uses one structure per scored dimension. That keeps scores paired with the judge's explanation and constrains the final recommendation.

```ruby
class DimensionEvaluation < T::Struct
  const :score, Float
  const :reasoning, String
end

class SendRecommendation < T::Enum
  enums do
    Send = new("SEND")
    Revise = new("REVISE")
    Reject = new("REJECT")
  end
end

class AISDRJudge < DSPy::Signature
  description "Evaluate an AI-generated sales campaign against the supplied targeting and sender evidence"

  input do
    const :target_criteria, TargetCriteria
    const :prospect_profile, ProspectProfile
    const :email_campaign, EmailCampaign
    const :sender_context, SenderContext
  end

  output do
    const :prospect_relevance, DimensionEvaluation
    const :personalization, DimensionEvaluation
    const :value_proposition, DimensionEvaluation
    const :professionalism, DimensionEvaluation
    const :compliance, DimensionEvaluation
    const :overall_quality_score, Float,
      description: "Overall campaign quality from 0.0 to 1.0"
    const :send_recommendation, SendRecommendation
  end
end
```

Typed output prevents misspelled recommendation values and rejects malformed result shapes. It does not validate the substance of the judgment.

## Turn The Judge Into A Metric

Configure the judge once, outside the metric. The metric then adapts each program prediction into judge inputs and returns the shape `DSPy::Evals` expects.

```ruby
judge_lm = DSPy::LM.new(
  "openai/gpt-4o-mini",
  api_key: ENV["OPENAI_API_KEY"]
)

judge = DSPy::ChainOfThought.new(AISDRJudge)
judge.configure { |config| config.lm = judge_lm }

ai_sdr_judge_metric = lambda do |example, prediction|
  next { passed: false, score: 0.0 } unless prediction

  request = if example.respond_to?(:input_values)
    example.input_values[:campaign_request]
  else
    example.dig(:input, :campaign_request)
  end
  output = prediction.sdr_output

  judgment = judge.call(
    target_criteria: TargetCriteria.new(
      role: request.target_role,
      company: request.target_company,
      industry: request.target_industry,
      seniority_level: request.seniority_level,
      department: request.department
    ),
    prospect_profile: output.prospect,
    email_campaign: output.email,
    sender_context: SenderContext.new(
      company: output.sender_company,
      value_proposition: request.value_proposition,
      industry_focus: request.industry_focus,
      case_studies: request.case_studies
    )
  )

  weights = {
    prospect_relevance: 0.25,
    personalization: 0.25,
    value_proposition: 0.20,
    professionalism: 0.15,
    compliance: 0.15
  }

  score = weights.sum do |name, weight|
    judgment.public_send(name).score * weight
  end

  {
    passed: judgment.send_recommendation == SendRecommendation::Send && score >= 0.7,
    score: score,
    recommendation: judgment.send_recommendation.serialize,
    judgment: judgment
  }
rescue StandardError => e
  DSPy.logger.warn("LLM judge evaluation failed: #{e.message}")
  { passed: false, score: 0.0, error: e.message }
end
```

A bare numeric return value would be treated as truthy by `DSPy::Evals`; it would not become the batch's numeric score. Returning `{ passed:, score: }` preserves both the release decision and the continuous measurement.

The weights and the `0.7` threshold are application policy. Start with values you can explain, then calibrate them against reviewed examples.

## Evaluate The Generator

The campaign generator remains a separate program. The judge metric evaluates its observable output.

```ruby
class CampaignRequest < T::Struct
  const :target_role, String
  const :target_company, String
  const :target_industry, String
  const :value_proposition, String
  const :seniority_level, T.nilable(String)
  const :department, T.nilable(String)
  const :industry_focus, T.nilable(String)
  const :case_studies, T.nilable(T::Array[String])
end

class SDRCampaignOutput < T::Struct
  const :prospect, ProspectProfile
  const :email, EmailCampaign
  const :sender_company, String
  const :confidence_score, Float
  const :reasoning, T.nilable(String)
end

class AISDRSignature < DSPy::Signature
  description "Generate a prospect and sales email for the supplied campaign"

  input do
    const :campaign_request, CampaignRequest
  end

  output do
    const :sdr_output, SDRCampaignOutput
  end
end
```

The judge does not compare the generator with a reference `SDRCampaignOutput`, so these evaluation cases use the hash input format supported by `DSPy::Evals`:

```ruby
requests = [
  CampaignRequest.new(
    target_role: "VP of Engineering",
    target_company: "TechCorp",
    target_industry: "Software",
    value_proposition: "Reduce deployment time with our DevOps platform",
    seniority_level: "Executive",
    department: "Engineering",
    industry_focus: "Enterprise Software",
    case_studies: ["A reviewed customer case study"]
  )
]

examples = requests.map do |request|
  { input: { campaign_request: request } }
end

program = DSPy::Predict.new(AISDRSignature)
result = DSPy::Evals.new(
  program,
  metric: ai_sdr_judge_metric
).evaluate(examples)

puts "Average judge score: #{result.score}%"
puts "Approved: #{result.passed_examples}/#{result.total_examples}"
```

The batch `score` is already a percentage. `pass_rate` is the fraction of examples that met the explicit send decision.

## Keep The Reasons Inspectable

The metric stores the typed judgment with each result:

```ruby
result.results.each do |example_result|
  judgment = example_result.metrics[:judgment]

  if judgment
    puts "Recommendation: #{judgment.send_recommendation.serialize}"
    puts "Prospect fit: #{judgment.prospect_relevance.score}"
    puts judgment.prospect_relevance.reasoning
    puts "Personalization: #{judgment.personalization.score}"
    puts judgment.personalization.reasoning
  else
    puts "Judge error: #{example_result.metrics[:error]}"
  end
end
```

Reasoning helps a reviewer inspect the decision. It should not be mistaken for proof that the score is correct. Store the source evidence, generated campaign, model configuration, metric version, and judgment together so disagreements can be reproduced.

## Calibrate Before Automating A Send Decision

Build a set of campaigns reviewed by people responsible for sales quality, brand risk, and compliance. Then compare the judge with those decisions.

Calibration should measure more than correlation:

- Agreement on `SEND`, `REVISE`, and `REJECT`.
- False approvals, especially unsupported claims and compliance failures.
- Score variance across repeated judge calls.
- Performance across industries, languages, and prospect groups.
- Drift after changing the judge model, signature, or evidence shape.

There is no universal target such as `correlation > 0.8` that makes a judge safe. The acceptable error rate depends on what happens after approval. For high-consequence categories, route the result to a person or a deterministic policy check.

## Multiple Judges Add Cost, Not Automatic Consensus

Specialized judges can separate prospect fit, copy quality, and compliance. Run independent calls concurrently when the provider clients and application runtime support it, then combine explicit typed results.

Three similar prompts against the same model are not three independent experts. Majority vote can repeat the same bias with three invoices. Use multiple judges when they have distinct rubrics or models and when calibration shows that the combination improves decisions.

## Optimize Against Human Evidence

Once you have human-rated campaigns and a stable metric, an optimizer can compile supported judge parameters such as instructions and demonstrations.

```ruby
human_agreement = lambda do |example, prediction|
  prediction.send_recommendation.serialize ==
    example.expected_values[:send_recommendation]
end

optimizer = DSPy::Teleprompt::MIPROv2.new(metric: human_agreement)
result = optimizer.compile(
  DSPy::ChainOfThought.new(AISDRJudge),
  trainset: human_rated_train,
  valset: human_rated_validation
)

optimized_judge = result.optimized_program
```

Compile the judge and generator in separate experiments. Otherwise a changed generator can hide a worse judge, or a changed judge can make an unchanged generator look better. Evaluate the selected artifacts on held-out human ratings before promoting them.

The [evaluation guide](/dspy.rb/optimization/evaluation/) covers result handling and metrics. See [custom metrics](/dspy.rb/advanced/custom-metrics/) for richer score shapes and [prompt optimization](/dspy.rb/optimization/prompt-optimization/) for supported compilation workflows.
