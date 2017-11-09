describe 'database' do
  before do
    `rm -rf test.db`
  end

  def run_script(commands)
    raw_output = nil
    IO.popen("./db test.db", "r+") do |pipe|
      commands.each do |command|
        begin
          pipe.puts command
        rescue Errno::EPIPE
          break
        end
      end

      pipe.close_write

      # Read entire output
      raw_output = pipe.gets(nil)
    end
    raw_output.split("\n")
  end

  it 'inserts and retreives a row' do
    result = run_script([
      "insert 1 user1 person1@example.com",
      "select",
      ".exit",
    ])
    expect(result).to eq([
      "db > Executed.",
      "db > (1, user1, person1@example.com)",
      "Executed.",
      "db > ",
    ])
  end

  it 'keeps data after closing connection' do
    result1 = run_script([
      "insert 1 user1 person1@example.com",
      ".exit",
    ])
    expect(result1).to eq([
      "db > Executed.",
      "db > ",
    ])

    result2 = run_script([
      "select",
      ".exit",
    ])
    expect(result2).to eq([
      "db > (1, user1, person1@example.com)",
      "Executed.",
      "db > ",
    ])
  end

  it 'prints error message when table is full' do
    script = (1..1401).map do |i|
      "insert #{i} user#{i} person#{i}@example.com"
    end
    script << ".exit"
    result = run_script(script)
    expect(result.last(2)).to eq([
      "db > Executed.",
      "db > Need to implement updating parent after split",
    ])
  end

  it 'allows inserting strings that are the maximum length' do
    long_username = "a"*32
    long_email = "a"*255
    script = [
      "insert 1 #{long_username} #{long_email}",
      "select",
      ".exit",
    ]
    result = run_script(script)
    expect(result).to eq([
      "db > Executed.",
      "db > (1, #{long_username}, #{long_email})",
      "Executed.",
      "db > ",
    ])
  end

  it 'prints error message if strings are too long' do
    long_username = "a"*33
    long_email = "a"*256
    script = [
      "insert 1 #{long_username} #{long_email}",
      "select",
      ".exit",
    ]
    result = run_script(script)
    expect(result).to eq([
      "db > String is too long.",
      "db > Executed.",
      "db > ",
    ])
  end

  it 'prints an error message if id is negative' do
    script = [
      "insert -1 cstack foo@bar.com",
      "select",
      ".exit",
    ]
    result = run_script(script)
    expect(result).to eq([
      "db > ID must be positive.",
      "db > Executed.",
      "db > ",
    ])
  end

  it 'prints an error message if there is a duplicate id' do
    script = [
      "insert 1 user1 person1@example.com",
      "insert 1 user1 person1@example.com",
      "select",
      ".exit",
    ]
    result = run_script(script)
    expect(result).to eq([
      "db > Executed.",
      "db > Error: Duplicate key.",
      "db > (1, user1, person1@example.com)",
      "Executed.",
      "db > ",
    ])
  end

  it 'allows printing out the structure of a one-node btree' do
    script = [3, 1, 2].map do |i|
      "insert #{i} user#{i} person#{i}@example.com"
    end
    script << ".btree"
    script << ".exit"
    result = run_script(script)

    expect(result).to eq([
      "db > Executed.",
      "db > Executed.",
      "db > Executed.",
      "db > Tree:",
      "- leaf (size 3)",
      "  - 1",
      "  - 2",
      "  - 3",
      "db > "
    ])
  end

  it 'allows printing out the structure of a 3-leaf-node btree' do
    script = (1..14).map do |i|
      "insert #{i} user#{i} person#{i}@example.com"
    end
    script << ".btree"
    script << "insert 15 user15 person15@example.com"
    script << ".exit"
    result = run_script(script)

    expect(result[14...(result.length)]).to eq([
      "db > Tree:",
      "- internal (size 1)",
      "  - leaf (size 7)",
      "    - 1",
      "    - 2",
      "    - 3",
      "    - 4",
      "    - 5",
      "    - 6",
      "    - 7",
      "  - key 7",
      "  - leaf (size 7)",
      "    - 8",
      "    - 9",
      "    - 10",
      "    - 11",
      "    - 12",
      "    - 13",
      "    - 14",
      "db > Executed.",
      "db > ",
    ])
  end

  it 'prints all rows in a multi-level tree' do
    script = []
    (1..15).each do |i|
      script << "insert #{i} user#{i} person#{i}@example.com"
    end
    script << "select"
    script << ".exit"
    result = run_script(script)

    expect(result[15...result.length]).to eq([
      "db > (1, user1, person1@example.com)",
      "(2, user2, person2@example.com)",
      "(3, user3, person3@example.com)",
      "(4, user4, person4@example.com)",
      "(5, user5, person5@example.com)",
      "(6, user6, person6@example.com)",
      "(7, user7, person7@example.com)",
      "(8, user8, person8@example.com)",
      "(9, user9, person9@example.com)",
      "(10, user10, person10@example.com)",
      "(11, user11, person11@example.com)",
      "(12, user12, person12@example.com)",
      "(13, user13, person13@example.com)",
      "(14, user14, person14@example.com)",
      "(15, user15, person15@example.com)",
      "Executed.", "db > ",
    ])
  end

  it 'prints constants' do
    script = [
      ".constants",
      ".exit",
    ]
    result = run_script(script)

    expect(result).to eq([
      "db > Constants:",
      "ROW_SIZE: 293",
      "COMMON_NODE_HEADER_SIZE: 6",
      "LEAF_NODE_HEADER_SIZE: 14",
      "LEAF_NODE_CELL_SIZE: 297",
      "LEAF_NODE_SPACE_FOR_CELLS: 4082",
      "LEAF_NODE_MAX_CELLS: 13",
      "db > ",
    ])
  end
end
