-- needspace-images.lua — Prevent page breaks between images and their captions.
--
-- Figure captions are placed below diagrams in the source markdown.
-- This filter inserts \needspace before image paragraphs so the image
-- and whatever follows (caption) stay on the same page.

function Blocks(blocks)
  local new = pandoc.List()

  for i = 1, #blocks do
    local blk = blocks[i]

    if blk.t == "Para" and #blk.content == 1 and blk.content[1].t == "Image" then
      new:insert(pandoc.RawBlock("latex", "\\needspace{6cm}"))
    end

    new:insert(blk)
  end

  return new
end
