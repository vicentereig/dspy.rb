---
layout: default
title: "DSPy.rb Blog"
description: "Practical insights and tutorials for building AI applications with Ruby"
---

<div class="bg-white py-24 sm:py-32">
  <div class="mx-auto max-w-7xl px-6 lg:px-8">
    <div class="mx-auto max-w-2xl text-center">
      <h2 class="text-3xl font-bold tracking-tight text-gray-900 sm:text-4xl">DSPy.rb Blog</h2>
      <p class="mt-2 text-lg leading-8 text-gray-600">Practical insights and tutorials for building AI applications with Ruby.</p>
    </div>
    
    <div class="mx-auto mt-16 grid max-w-2xl grid-cols-1 gap-x-8 gap-y-12 lg:mx-0 lg:max-w-none lg:grid-cols-3">
      {% assign sorted_posts = site.pages | where: "layout", "blog" | sort: "date" | reverse %}
      {% for post in sorted_posts %}
        <article class="flex flex-col items-start">
          <div class="relative w-full">
            <div class="aspect-[16/9] w-full rounded-2xl bg-gradient-to-br from-red-600 to-red-700 sm:aspect-[2/1] lg:aspect-[3/2]">
              <div class="flex h-full items-center justify-center">
                <div class="text-center p-6">
                  <svg class="mx-auto h-12 w-12 text-white opacity-50" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 6.042A8.967 8.967 0 006 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 016 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 016-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0018 18a8.967 8.967 0 00-6 2.292m0-14.25v14.25" />
                  </svg>
                </div>
              </div>
            </div>
            <div class="absolute inset-0 rounded-2xl ring-1 ring-inset ring-gray-900/10"></div>
          </div>
          
          <div class="max-w-xl">
            <div class="mt-8 flex items-center gap-x-4 text-xs">
              <time datetime="{{ post.date | date: '%Y-%m-%d' }}" class="text-gray-500">
                {{ post.date | date: "%B %d, %Y" }}
              </time>
              {% if post.category %}
                <span class="relative z-10 rounded-full bg-gray-50 px-3 py-1.5 font-medium text-gray-600 hover:bg-gray-100">
                  {{ post.category }}
                </span>
              {% endif %}
            </div>
            
            <div class="group relative">
              <h3 class="mt-3 text-lg font-semibold leading-6 text-gray-900 group-hover:text-gray-600">
                <a href="{{ post.url | relative_url }}">
                  <span class="absolute inset-0"></span>
                  {{ post.title }}
                </a>
              </h3>
              <p class="mt-5 line-clamp-3 text-sm leading-6 text-gray-600">
                {{ post.description }}
              </p>
            </div>
            
            <div class="relative mt-8 flex items-center gap-x-4">
              <div class="h-10 w-10 rounded-full bg-gradient-to-br from-red-600 to-red-700 flex items-center justify-center">
                <span class="text-sm font-bold text-white">{{ post.author | default: "DSPy" | slice: 0, 1 }}</span>
              </div>
              <div class="text-sm leading-6">
                <p class="font-semibold text-gray-900">
                  <span class="absolute inset-0"></span>
                  {{ post.author | default: "DSPy.rb Team" }}
                </p>
                {% if post.read_time %}
                  <p class="text-gray-600">{{ post.read_time }} min read</p>
                {% endif %}
              </div>
            </div>
          </div>
        </article>
      {% endfor %}
    </div>
    
    {% if sorted_posts.size == 0 %}
      <div class="mt-16 text-center">
        <p class="text-gray-500">No blog posts yet. Check back soon!</p>
      </div>
    {% endif %}
  </div>
</div>