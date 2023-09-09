require "bundler/inline"

gemfile do
  source "https://rubygems.org"

  gem "pry-byebug"
  gem "facter"
end

require "open3"
require "json"
require "logger"
require "time"
require "pathname"
require "net/http"

ROOT_DIR = Pathname.new(__dir__)
RESULTS_DIR = ROOT_DIR.join("results")

class BenchmarkRunner
  SECONDS = 30
  GRAPHQL_VERSIONS = JSON.parse(Net::HTTP.get(URI("https://rubygems.org/api/v1/versions/graphql.json"))).map { _1['number'] }.map { Gem::Version.new(_1) }.select { !_1.prerelease? && _1 >= Gem::Version.new("0.1.0") }

  LOGGER = Logger.new(STDOUT)

  def run
    target_versions = GRAPHQL_VERSIONS.select { _1 >= Gem::Version.new("2.0.0") }

    result = target_versions.map(&:version).flat_map do |graphql_version|
      LOGGER.info("Start benchmark for #{graphql_version}")

      matrix = if false
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

      matrix.map do |data|
        field_count, object_count = data.values_at(:field_count, :object_count)
        LOGGER.info("field_count: #{field_count}, object_count: #{object_count}")

        result = benchmark(graphql_version: graphql_version, field_count: field_count, object_count: object_count, seconds: SECONDS)

        {
          ruby_version: RUBY_VERSION,
          graphql_version: graphql_version,
          field_count: field_count,
          object_count: object_count,
          iteration_count: result[:iteration_count],
          time: result[:time],
          ips: result[:iteration_count] / result[:time],
          processors: Facter["processors"].value,
        }
      end
    end

    RESULTS_DIR.join("result-#{Time.now.iso8601}.json").write(JSON.pretty_generate(result))
  end

  private

  def benchmark(graphql_version:, field_count:, object_count:, seconds:)
    read, write = IO.pipe
    pid = Process.fork do
      ENV["GRAPHQL_VERSION"] = graphql_version
      ENV["FIELD_COUNT"] = field_count.to_s
      ENV["OBJECT_COUNT"] = object_count.to_s

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

BenchmarkRunner.new.run
