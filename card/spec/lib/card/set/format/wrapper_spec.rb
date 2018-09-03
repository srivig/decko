RSpec.describe Card::Set::Format::Wrapper do
  describe "simple wrapper" do
    let(:format) do
      Card["A"].format_with do
        wrapper :cream do
          "cream_#{interiour}_cream"
        end

        wrapper :icon do
          icon_tag interiour
        end
      end
    end

    subject do
      format.wrap_with_cream { "cake" }
    end

    it "is wrapped with cream" do
      is_expected.to  eq "cream_cake_cream"
    end

    it "is possible to use format methods in wrapper" do
      expect(format.wrap_with_icon("edit")).to have_tag :i, "edit"
    end
  end

  describe "html tag wrapper" do
    let(:format) do
      Card["A"].format_with do
        wrapper :cream, :div, class: "creamy"
      end
    end

    context "when called with block" do
      subject do
        format.wrap_with_cream { "cake" }
      end

      it "is wrapped with cream" do
        is_expected.to have_tag "div.creamy", "cake"
      end
    end

    context "when called with content argument" do
      subject do
        format.wrap_with_cream "cake"
      end

      it "is wrapped with cream" do
        is_expected.to have_tag "div.creamy", "cake"
      end
    end
  end

  describe "wrapper with options" do
    let(:format) do
      Card["A"].format_with do
        wrapper :cream do |opts|
          "#{opts[:topping]}_cream_#{interiour}_cream"
        end
      end
    end

    subject do
      format.wrap_with_cream(topping: "cherry") { "cake" }
    end

    it "is wrapped with cream" do
      is_expected.to eq "cherry_cream_cake_cream"
    end
  end

  describe "wrapper as view setting" do
    let(:format) do
      Card["A"].format_with do
        wrapper :cream do
          "cream_#{interiour}_cream"
        end

        view :cream_cake, wrap: :cream do
          "cake"
        end
      end
    end

    subject { format.render_cream_cake }

    it "is wrapped with cream" do
      is_expected.to eq "cream_cake_cream"
    end
  end

  describe "nested wrapper" do
    let(:format) do
      Card["A"].format_with do
        view :kwai, wrap: :bridge do
          "water"
        end
      end
    end

    subject { format.render_kwai }

    it "wrapped with bridge" do
      is_expected.to have_tag "sadf"
    end
  end


end
