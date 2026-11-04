///|
/// Process entry point: collect argv, run the command tree, and map failures to
/// a non-zero exit status with a Cobra-like `Error:` prefix.
async fn main {
  let args = @env.args()
  let command_args : Array[String] = []
  for index in 1..<args.length() {
    command_args.push(args[index])
  }
  match @cli.run_cli(command_args) {
    Ok(_) => ()
    Err(message) => {
      @stdio.stderr.write("Error: " + message + "\n")
      @cli.exit_with(1)
    }
  }
}
