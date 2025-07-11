---
layout: default
title: "DSPy.rb Blog"
description: "Practical insights and tutorials for building AI applications with Ruby"
---

<div class="relative isolate overflow-hidden bg-white">
  <!-- Background gradient -->
  <div class="absolute inset-x-0 -top-40 -z-10 transform-gpu overflow-hidden blur-3xl sm:-top-80" aria-hidden="true">
    <div class="relative left-[calc(50%-11rem)] aspect-[1155/678] w-[36.125rem] -translate-x-1/2 rotate-[30deg] bg-gradient-to-tr from-[#ff80b5] to-[#9089fc] opacity-30 sm:left-[calc(50%-30rem)] sm:w-[72.1875rem]"></div>
  </div>
  
  <div class="mx-auto max-w-7xl px-6 py-24 sm:py-32 lg:px-8">
    <!-- Header -->
    <div class="mx-auto max-w-2xl text-center">
      <h1 class="text-4xl font-bold tracking-tight text-gray-900 sm:text-6xl">
        DSPy.rb Blog
      </h1>
      <p class="mt-6 text-lg leading-8 text-gray-600">
        Practical insights and tutorials for building AI applications with Ruby. 
        Learn from real-world examples and expert techniques.
      </p>
    </div>
    
    <!-- Blog posts grid -->
    <div class="mx-auto mt-20 grid max-w-2xl grid-cols-1 gap-x-8 gap-y-16 lg:mx-0 lg:max-w-none lg:grid-cols-3">
      {% assign blog_posts = site.pages | where: "layout", "blog" %}
      {% if blog_posts.size > 0 %}
        {% assign sorted_posts = blog_posts | sort: "date" | reverse %}
      {% else %}
        {% assign sorted_posts = blog_posts %}
      {% endif %}
      {% for post in sorted_posts %}
        <article class="flex flex-col items-start justify-between">
          <div class="relative w-full">
            <div class="aspect-[16/9] w-full rounded-2xl bg-gradient-to-br from-dspy-ruby to-red-700 shadow-lg overflow-hidden">
              <div class="absolute inset-0 bg-gradient-to-br from-dspy-ruby/90 to-red-700/90"></div>
              <div class="relative flex h-full items-center justify-center p-8">
                <div class="text-center">
                  {% if post.category == "Tutorial" %}
                    <svg class="mx-auto h-12 w-12 text-white/80" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M4.26 10.147a60.436 60.436 0 00-.491 6.347A48.627 48.627 0 0112 20.904a48.627 48.627 0 018.232-4.41 60.46 60.46 0 00-.491-6.347m-15.482 0a50.57 50.57 0 00-2.658-.813A59.905 59.905 0 0112 3.493a59.902 59.902 0 0110.399 5.84c-.896.248-1.783.52-2.658.814m-15.482 0A50.697 50.697 0 0112 13.489a50.702 50.702 0 017.74-3.342M6.75 15a.75.75 0 100-1.5.75.75 0 000 1.5zm0 0v-3.675A55.378 55.378 0 0112 8.443a55.381 55.381 0 015.25 2.882V15" />
                    </svg>
                  {% elsif post.category == "Features" %}
                    <svg class="mx-auto h-12 w-12 text-white/80" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M9.813 15.904L9 18.75l-.813-2.846a4.5 4.5 0 00-3.09-3.09L2.25 12l2.846-.813a4.5 4.5 0 003.09-3.09L9 5.25l.813 2.846a4.5 4.5 0 003.09 3.09L15.75 12l-2.846.813a4.5 4.5 0 00-3.09 3.09zM18.259 8.715L18 9.75l-.259-1.035a3.375 3.375 0 00-2.455-2.456L14.25 6l1.036-.259a3.375 3.375 0 002.455-2.456L18 2.25l.259 1.035a3.375 3.375 0 002.456 2.456L21.75 6l-1.035.259a3.375 3.375 0 00-2.456 2.456zM16.894 20.567L16.5 21.75l-.394-1.183a2.25 2.25 0 00-1.423-1.423L13.5 18.75l1.183-.394a2.25 2.25 0 001.423-1.423l.394-1.183.394 1.183a2.25 2.25 0 001.423 1.423l1.183.394-1.183.394a2.25 2.25 0 00-1.423 1.423z" />
                    </svg>
                  {% else %}
                    <svg class="mx-auto h-12 w-12 text-white/80" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M12 6.042A8.967 8.967 0 006 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 016 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 016-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0018 18a8.967 8.967 0 00-6 2.292m0-14.25v14.25" />
                    </svg>
                  {% endif %}
                  <div class="mt-4">
                    <span class="inline-flex items-center rounded-full bg-white/20 px-2.5 py-0.5 text-xs font-medium text-white">
                      {{ post.category | default: "Article" }}
                    </span>
                  </div>
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
              {% if post.read_time %}
                <span class="text-gray-500">{{ post.read_time }} min read</span>
              {% endif %}
            </div>
            
            <div class="group relative">
              <h3 class="mt-3 text-lg font-semibold leading-6 text-gray-900 group-hover:text-dspy-ruby transition-colors">
                <a href="{{ post.url | relative_url }}">
                  <span class="absolute inset-0"></span>
                  {{ post.title }}
                </a>
              </h3>
              <p class="mt-5 text-sm leading-6 text-gray-600 line-clamp-3">
                {{ post.description }}
              </p>
            </div>
            
            <div class="relative mt-8 flex items-center gap-x-4">
              <div class="h-10 w-10 rounded-full bg-gradient-to-br from-dspy-ruby to-red-700 flex items-center justify-center ring-2 ring-white shadow-lg">
                <span class="text-sm font-bold text-white">{{ post.author | default: "DSPy" | slice: 0, 1 }}</span>
              </div>
              <div class="text-sm leading-6">
                <p class="font-semibold text-gray-900">
                  {{ post.author | default: "DSPy.rb Team" }}
                </p>
                <p class="text-gray-600">Lead Developer</p>
              </div>
            </div>
          </div>
        </article>
      {% endfor %}
    </div>
    
    {% if sorted_posts.size == 0 %}
      <div class="mt-16 text-center">
        <div class="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-gray-100">
          <svg class="h-6 w-6 text-gray-400" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 6.042A8.967 8.967 0 006 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 016 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 016-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0018 18a8.967 8.967 0 00-6 2.292m0-14.25v14.25" />
          </svg>
        </div>
        <h3 class="mt-4 text-sm font-semibold text-gray-900">No blog posts yet</h3>
        <p class="mt-2 text-sm text-gray-500">Check back soon for new content!</p>
      </div>
    {% endif %}
  </div>
  
  <!-- Bottom background gradient -->
  <div class="absolute inset-x-0 top-[calc(100%-13rem)] -z-10 transform-gpu overflow-hidden blur-3xl sm:top-[calc(100%-30rem)]" aria-hidden="true">
    <div class="relative left-[calc(50%+3rem)] aspect-[1155/678] w-[36.125rem] -translate-x-1/2 bg-gradient-to-tr from-[#ff80b5] to-[#9089fc] opacity-30 sm:left-[calc(50%+36rem)] sm:w-[72.1875rem]"></div>
  </div>
</div>