const esbuild = require("esbuild")

const defineEnv = (mode) => {
  const env = {}
  
  if (mode === "development") {
    env.BRIDGETOWN_ENV = "development"
  } else {
    env.BRIDGETOWN_ENV = "production"
  }

  return Object.keys(env).reduce((acc, key) => {
    acc[`process.env.${key}`] = JSON.stringify(env[key])
    return acc
  }, {})
}

const buildOptions = (mode = "production") => ({
  entryPoints: ["frontend/javascript/index.js"],
  outdir: "output/_bridgetown/static/js",
  bundle: true,
  minify: mode === "production",
  sourcemap: mode === "development",
  target: ["es2017"],
  define: defineEnv(mode),
  publicPath: "/_bridgetown/static/js/",
})

const cssOptions = (mode = "production") => ({
  entryPoints: ["frontend/styles/index.css"],
  outdir: "output/_bridgetown/static/css",
  bundle: true,
  minify: mode === "production",
  sourcemap: mode === "development",
  publicPath: "/_bridgetown/static/css/",
})

if (require.main === module) {
  const mode = process.argv.includes("--watch") ? "development" : "production"
  
  if (process.argv.includes("--watch")) {
    const jsContext = esbuild.context(buildOptions(mode))
    const cssContext = esbuild.context(cssOptions(mode))
    
    Promise.all([jsContext, cssContext]).then(([js, css]) => {
      js.watch()
      css.watch()
      console.log("👀 Watching for changes...")
    })
  } else {
    Promise.all([
      esbuild.build(buildOptions(mode)),
      esbuild.build(cssOptions(mode))
    ]).then(() => {
      console.log("⚡ Build complete!")
    }).catch((error) => {
      console.error(error)
      process.exit(1)
    })
  }
}

module.exports = { buildOptions, cssOptions }
