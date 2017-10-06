require 'spec_helper'
require 'support/helpers'

RSpec.describe 'Edge' do
  include TypedDag::Specs::Helpers
  # using Relation, Message as the concrete classes

  let(:from) { Message.new text: 'from' }
  let(:to) { Message.new text: 'to' }
  let(:relation) do
    Relation.new from: from,
                 to: to,
                 hierarchy: 1
  end

  describe 'validations' do
    it 'is valid' do
      expect(relation)
        .to be_valid
    end

    context 'without an from' do
      let(:from) { nil }

      it 'is invalid' do
        expect(relation)
          .to be_invalid
      end

      it 'states the error' do
        relation.valid?

        expect(relation.errors.details[:from])
          .to match_array([error: :blank])
      end
    end

    context 'without a to' do
      let(:to) { nil }

      it 'is invalid' do
        expect(relation)
          .to be_invalid
      end

      it 'states the error' do
        relation.valid?

        expect(relation.errors.details[:to])
          .to match_array([error: :blank])
      end
    end

    context 'with a relation already in place between the two nodes' do
      let!(:same_relation) do
        Relation.create from: from,
                        to: to
      end

      it 'is invalid' do
        expect(relation)
          .to be_invalid
      end

      it 'notes the uniqueness constraint' do
        relation.valid?

        expect(relation.errors.details[:from].first[:error])
          .to eql :taken
      end
    end

    context 'with a relation already in place between the two nodes having a different type' do
      let!(:same_relation) do
        Relation.create from: from,
                        to: to,
                        invalidate: 1
      end

      it 'is invalid' do
        expect(relation)
          .to be_invalid
      end

      it 'notes the uniqueness constraint' do
        relation.valid?

        expect(relation.errors.details[:from].first[:error])
          .to eql :taken
      end
    end

    context 'with a closure relation already in place between the two nodes (same type)' do
      let!(:closure_relation) do
        Relation.create from: from,
                        to: to,
                        invalidate: 2
      end

      it 'is valid' do
        expect(relation)
          .to be_valid
      end
    end

    context 'with a closure relation already in place between the two nodes (mixed type)' do
      let!(:closure_relation) do
        Relation.create from: from,
                        to: to,
                        invalidate: 1,
                        hierarchy: 1
      end

      it 'is valid' do
        expect(relation)
          .to be_valid
      end
    end

    context 'with a relation in place but in the other direction' do
      let(:inverse_relation) do
        Relation.create to: from,
                        from: to,
                        hierarchy: 1
      end

      before do
        inverse_relation
      end

      it 'is invalid' do
        expect(relation)
          .to be_invalid
      end
    end

    context 'with A - B - C and trying to connect C and A' do
      let(:a) { Message.create text: 'A' }
      let(:b) { Message.create text: 'B' }
      let(:c) { Message.create text: 'C' }
      let!(:relationAB) do
        Relation.create from: a,
                        to: b,
                        hierarchy: 1
      end
      let!(:relationBC) do
        Relation.create from: b,
                        to: c,
                        hierarchy: 1
      end
      let(:from) { c }
      let(:to) { b }

      it 'is invalid' do
        expect(relation)
          .to be_invalid
      end
    end

    context 'with A - B - C (different type) already related and trying to connect C and A' do
      let(:a) { Message.create text: 'A' }
      let(:b) { Message.create text: 'B' }
      let(:c) { Message.create text: 'C' }
      let!(:relationAB) do
        Relation.create from: a,
                        to: b,
                        invalidate: 1
      end
      let!(:relationBC) do
        Relation.create from: b,
                        to: c,
                        hierarchy: 1
      end
      let(:from) { c }
      let(:to) { b }

      it 'is invalid' do
        expect(relation)
          .to be_invalid
      end
    end
  end

  describe '.direct' do
    description = <<-'WITH'

      DAG:
                 ------- A -------
                /                 \
          invalidate            hierarchy
              /                     \
             B                       C
             |                       |
         hierarchy               hierarchy
             |                       |
             D                       E

    WITH
    context description do
      let!(:a) { Message.create text: 'A' }
      let!(:b) { create_message_with_invalidated_by('B', a) }
      let!(:c) { Message.create text: 'C', parent: a }
      let!(:d) { Message.create text: 'D', parent: b }
      let!(:e) { Message.create text: 'E', parent: c }

      it 'returns only the relations that have no hops' do
        expect(Relation.direct.map { |r| [r.from.text, r.to.text] })
          .to match_array [['A', 'B'], ['B', 'D'], ['A', 'C'], ['C', 'E']]
      end
    end
  end

  describe '#direct?' do
    context 'for a relation having invalidate = 1' do
      let(:relation) { Relation.new invalidate: 1 }

      it 'is true' do
        expect(relation)
          .to be_direct
      end
    end

    context 'for a relation having invalidate = 2' do
      let(:relation) { Relation.new invalidate: 2 }

      it 'is true' do
        expect(relation)
          .not_to be_direct
      end
    end

    context 'for a relation having invalidate = 1 and hierarchy = 1' do
      let(:relation) { Relation.new invalidate: 1, hierarchy: 1 }

      it 'is true' do
        expect(relation)
          .not_to be_direct
      end
    end
  end

  describe 'type selection scopes' do
    description = <<-'WITH'

      DAG:
                 ------- A -------
                /                 \
          invalidate            hierarchy
              /                     \
             B                       C
            / \                      |
   hierarchy   invalidate         hierarchy
          /     \                    |
         D       E                   F

    WITH
    context description do
      let!(:a) { Message.create text: 'A' }
      let!(:b) { create_message_with_invalidated_by('B', a) }
      let!(:c) { Message.create text: 'C', parent: a }
      let!(:d) { Message.create text: 'D', parent: b }
      let!(:e) { create_message_with_invalidated_by('E', b) }
      let!(:f) { Message.create text: 'F', parent: c }

      it 'returns all hierarchy relations (including transtitive) for #hierarchy' do
        expect(Relation.hierarchy.map { |r| [r.from.text, r.to.text, r.hierarchy, r.invalidate ] })
          .to match_array [['B', 'D', 1, 0],
                           ['A', 'C', 1, 0],
                           ['C', 'F', 1, 0],
                           ['A', 'F', 2, 0]]
      end

      it 'returns all invalidate relations (including transtitive) for #invalidate' do
        expect(Relation.invalidate.map { |r| [r.from.text, r.to.text, r.hierarchy, r.invalidate ] })
          .to match_array [['A', 'B', 0, 1],
                           ['B', 'E', 0, 1],
                           ['A', 'E', 0, 2]]
      end

      it 'returns all non hierarchy relations (including transtitive) for #non_hierarchy' do
        expect(Relation.non_hierarchy.map { |r| [r.from.text, r.to.text, r.hierarchy, r.invalidate ] })
          .to match_array [['A', 'B', 0, 1],
                           ['B', 'E', 0, 1],
                           ['A', 'E', 0, 2]]
      end

      it 'returns all non invalidate relations (including transtitive) for #non_invalidate' do
        expect(Relation.non_invalidate.map { |r| [r.from.text, r.to.text, r.hierarchy, r.invalidate ] })
          .to match_array [['B', 'D', 1, 0],
                           ['A', 'C', 1, 0],
                           ['C', 'F', 1, 0],
                           ['A', 'F', 2, 0]]
      end
    end
  end
end