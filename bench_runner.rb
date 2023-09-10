require "bundler/inline"

gemfile do
  source "https://rubygems.org"

  gem "pry-byebug"
  gem "facter"
  gem "octokit"
  gem "faraday-retry"
end

require "open3"
require "json"
require "logger"
require "time"
require "pathname"
require "net/http"
require "optparse"

ROOT_DIR = Pathname.new(__dir__)
RESULTS_DIR = ROOT_DIR.join("results")

class BenchmarkRunner
  SECONDS = 30
  GRAPHQL_VERSIONS = JSON.parse(Net::HTTP.get(URI("https://rubygems.org/api/v1/versions/graphql.json"))).map { _1['number'] }.map { Gem::Version.new(_1) }.select { !_1.prerelease? && _1 >= Gem::Version.new("0.1.0") }

  LOGGER = Logger.new(STDOUT)

  def run_performance_prs
    gh_client = Octokit::Client.new

    matrix = [
      4433,
      4436,
      4428,
      4430,
      4427,
      4399,
      4453,
      4450,
      4452,
      4449
    ].flat_map do |num|
      pr = gh_client.pull_request("rmosolgo/graphql-ruby", num)

      [
        pr.merge_commit_sha,
        pr.base.sha
      ].map do |graphql_version|
        {field_count: 100, object_count: 1000, graphql_version:, use_github: true, additional_info: {pr: num, base_sha: pr.base.sha, merge_commit_sha: pr.merge_commit_sha}}
      end
    end

    run(matrix, "performance_prs")
  end

  def run_released_versions
    target_versions = GRAPHQL_VERSIONS.select { _1 >= Gem::Version.new("2.0.0") }

    matrix = target_versions.map(&:version).flat_map do |graphql_version|
      data = if false
        [
          {field_count: 1, object_count: 1000},
          {field_count: 10, object_count: 1000},
          {field_count: 100, object_count: 1000},
          {field_count: 300, object_count: 1000},
          {field_count: 500, object_count: 1000},
          {field_count: 700, object_count: 1000},
          {field_count: 1000, object_count: 1000},
          {field_count: 100, object_count: 1},
          {field_count: 100, object_count: 10},
          {field_count: 100, object_count: 100},
          {field_count: 100, object_count: 1000},
          {field_count: 100, object_count: 10000},
        ].uniq
      else
        [
          {field_count: 100, object_count: 1000}
        ]
      end
      data.merge(graphql_version:)
    end

    run(matrix, "released_versions")
  end

  private

  def run(matrix, variation_name)
    result = matrix.map do |data|
      LOGGER.info("Start benchmark for #{data.inspect}")

      graphql_version, field_count, object_count, use_github, additional_info = data.values_at(:graphql_version, :field_count, :object_count, :use_github, :additional_info)

      result = benchmark(graphql_version:, field_count:, object_count:, use_github:, seconds: SECONDS)

      {
        ruby_version: RUBY_VERSION,
        graphql_version: graphql_version,
        field_count: field_count,
        object_count: object_count,
        iteration_count: result[:iteration_count],
        time: result[:time],
        ips: result[:iteration_count] / result[:time],
        processors: Facter["processors"].value,
      }.merge(additional_info || {})
    end

    RESULTS_DIR.join("result-#{variation_name}-#{Time.now.iso8601}.json").write(JSON.pretty_generate(result))
  end

  private

  def benchmark(graphql_version:, field_count:, object_count:, seconds:, use_github: false)
    read, write = IO.pipe
    pid = Process.fork do
      ENV["GRAPHQL_VERSION"] = graphql_version
      ENV["FIELD_COUNT"] = field_count.to_s
      ENV["OBJECT_COUNT"] = object_count.to_s
      ENV["USE_GITHUB"] = use_github ? "1" : "0"

      load ROOT_DIR.join("graphql.rb")

      iteration_count = 0
      started_at = Time.now
      time = nil

      loop do
        execute
        iteration_count += 1
        time = Time.now - started_at
        break if time >= seconds
      end

      write.puts iteration_count
      write.puts time
    end

    _, status = Process.waitpid2(pid, 0)
    unless status.success?
      raise "Something wrong"
    end
    write.close
    result = read.read
    read.close
    iteration_count, time = result.lines(chomp: true)
    {
      iteration_count: iteration_count.to_i,
      time: time.to_f
    }
  end
end

opt = OptionParser.new
params = {}
opt.on("--variation VAL") {|v| params[:variation] = v }
opt.parse!(ARGV)

case params[:variation]
when "released_versions"
  BenchmarkRunner.new.run_released_versions
when "performance_prs"
  BenchmarkRunner.new.run_performance_prs
end
