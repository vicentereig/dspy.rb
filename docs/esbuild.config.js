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

if (require.main === module) {
  const mode = process.argv.includes("--watch") ? "development" : "production"
  
  if (process.argv.includes("--watch")) {
    esbuild.context(buildOptions(mode)).then(ctx => {
      ctx.watch()
      console.log("👀 Watching for JavaScript changes...")
    })
  } else {
    esbuild.build(buildOptions(mode)).then(() => {
      console.log("⚡ JavaScript build complete!")
    }).catch((error) => {
      console.error(error)
      process.exit(1)
    })
  }
}

module.exports = { buildOptions }
