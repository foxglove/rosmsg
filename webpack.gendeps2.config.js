module.exports = {
  target: "node",
  mode: "production",
  entry: "./src/gendeps2.ts",
  output: {
    path: require("path").resolve(__dirname, "dist"),
    filename: "gendeps2.js",
    libraryTarget: "commonjs2",
  },
  devtool: "source-map",
  resolve: {
    extensions: [".js", ".ts", ".jsx", ".tsx", ".ne"],
  },
  optimization: {
    minimize: false,
  },
  module: {
    rules: [
      { test: /\.ne$/, loader: "nearley-loader" },
      {
        test: /\.tsx?$/,
        exclude: /node_modules/,
        use: [
          {
            loader: "ts-loader",
            options: {
              configFile: "tsconfig.json",
            },
          },
        ],
      },
    ],
  },
};
