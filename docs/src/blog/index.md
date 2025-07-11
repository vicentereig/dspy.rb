---
layout: default
title: "DSPy.rb Blog"
---

# DSPy.rb Blog

Practical insights and tutorials for building AI applications with Ruby.

<div class="not-prose mt-6 space-y-8">
  {% for post in site.pages %}
    {% if post.layout == 'blog' %}
      <article class="relative flex flex-col gap-8 lg:flex-row">
        <div class="relative aspect-[16/9] sm:aspect-[2/1] lg:aspect-square lg:w-64 lg:shrink-0">
          <div class="absolute inset-0 rounded-2xl bg-gray-100 dark:bg-gray-800"></div>
        </div>
        <div>
          <div class="flex items-center gap-x-4 text-xs">
            <time datetime="{{ post.date }}" class="text-gray-500 dark:text-gray-400">
              {{ post.date | date: "%B %d, %Y" }}
            </time>
            {% if post.category %}
              <span class="relative z-10 rounded-full bg-gray-50 dark:bg-gray-900 px-3 py-1.5 font-medium text-gray-600 dark:text-gray-400">
                {{ post.category }}
              </span>
            {% endif %}
          </div>
          <div class="group relative max-w-xl">
            <h3 class="mt-3 text-lg font-semibold leading-6 text-gray-900 dark:text-white group-hover:text-gray-600 dark:group-hover:text-gray-300">
              <a href="{{ post.url }}">
                <span class="absolute inset-0"></span>
                {{ post.title }}
              </a>
            </h3>
            <p class="mt-5 text-sm leading-6 text-gray-600 dark:text-gray-400">
              {{ post.description }}
            </p>
          </div>
          <div class="mt-6 flex border-t border-gray-900/5 dark:border-gray-100/5 pt-6">
            <div class="relative flex items-center gap-x-4">
              <div class="text-sm leading-6">
                <p class="font-semibold text-gray-900 dark:text-white">
                  {{ post.author | default: "DSPy.rb Team" }}
                </p>
              </div>
            </div>
          </div>
        </div>
      </article>
    {% endif %}
  {% endfor %}
</div>