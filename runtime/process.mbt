///|
pub async fn probe(program : String, args : Array[String], cwd : String) -> Int {
  let (code, _, _) = @process.collect_output(program[:], args[:], cwd=cwd[:])
  code
}
