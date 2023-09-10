require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'

  gem 'matplotlib', require: 'matplotlib/pyplot'
  gem 'pry-byebug'
end

require 'pathname'
require 'json'

ROOT_DIR = Pathname.new(__dir__)

path = ROOT_DIR.join('results/result-performance_prs-2023-09-10T03:38:18+00:00.json')

raw_data = JSON.parse(path.read)

plt = Matplotlib::Pyplot

data = raw_data.group_by { _1['pr'] }.map do |pr, results|
  base_sha, merge_commit_sha = results[0].values_at("base_sha", "merge_commit_sha")
  base_result = results.find { _1["graphql_version"] == base_sha }
  merge_result = results.find { _1["graphql_version"] == merge_commit_sha }

  {
    pr: pr,
    base_ips: base_result["ips"],
    merge_ips: merge_result["ips"],
    improve_ratio: merge_result["ips"] / base_result["ips"] - 1,
  }
end.sort_by { _1[:pr] }

xs = data.size.times.to_a
ys = data.map { _1[:improve_ratio] }

p ys

plt.bar(xs, ys, tick_label: data.map { _1[:pr] })
plt.grid
plt.xticks(rotation: 60)
plt.xlabel('PR number')
plt.ylabel('IPS improvement ratio (merge / base - 1)')
plt.title('IPS improvement (higher is better)')
plt.tight_layout
plt.savefig(ROOT_DIR.join("results/figs/#{path.basename.to_s.sub('.json', '.png')}").to_s)
