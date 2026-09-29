# Read package
#install.packages("ollamar")
library(ollamar)

test_connection()
pull("qwen3:1.7b")

# Configure model and submit prompt
model <- "qwen3:1.7b"
sample_string <- "asdf word 3"
prompt <- paste0(
    "extract the word count and character count from the following text string: ",
    sample_string,
    output = "df"
)
resp <- generate(model, prompt)
resp
# Status 200 OK indicates success

x <- resp_process(resp, "df")

#install.packages("ellmer")
library(ellmer)

# chat with local ollama
chat <- chat_ollama(
    system_prompt = "You are an investigator, attempting to investigate what restaurant people ate at, and what food they ate. You will be receiving inputs of individual narratives describing where they ate and what they ate. You should always extract a comma separated list of first the restaurant they ate at, then a comma separated list of foods they ate, contained within brackets",
    model = model,
    params = params(seed = 5, reasoning_effort = "none"),
    echo = "output"
)


input_narratives <- list(
    "I ate at a restaurant called Wendys today and I got a hamburger and a large fries",
    "I went to tacobell and I got two tacos doritos locos tacos",
    "I went to the burger place on the corner with the golden arches, and got a burger",
    " I went to the taco bell a few streets over and I bought a large coke"
)

output1 <- map(input_narratives, ~ chat$chat(.x))

# chat2 <- chat_ollama(
#     system_prompt = "You will receive a comma separated list of a restaurant, and a food consumed. Your task is to review all foods consumed across all restaurants, and unify the names. For example, 'large fries', 'french fries', and 'fries' all refer to the same food. You should therefore rename them all 'french fries' so that the text formatting is harmonized",
#     model = model,
#     params = params(seed = 5, reasoning_effort = "none"),
#     echo = "all"
# )

# output2 <- map(output1, ~ chat2$chat(.x))