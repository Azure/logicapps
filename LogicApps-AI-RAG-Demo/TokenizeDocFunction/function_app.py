import azure.functions as func
import logging
import base64
from io import BytesIO
from langchain.document_loaders import PyPDFLoader, TextLoader, UnstructuredHTMLLoader, UnstructuredPowerPointLoader, UnstructuredMarkdownLoader
from langchain.document_loaders.word_document import Docx2txtLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter, TokenTextSplitter, MarkdownHeaderTextSplitter, HTMLHeaderTextSplitter
import tiktoken
import json
import os
import tempfile

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

@app.route(route="tokenize_trigger")
def tokenize_trigger(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request.')

    output = main(req.get_json())
    
    resp = func.HttpResponse(
            body=output,
            status_code=200)
    return resp

def load_file(req):
    # accepts user input as a json object, decodes and returns the document data.
    loader_mapping = {
        "PDF": PyPDFLoader,
        "DOCUMENT": Docx2txtLoader,
        "MARKUP": UnstructuredMarkdownLoader,
        "TXT": TextLoader,
        "PPTX": UnstructuredPowerPointLoader,
        "HTML": UnstructuredHTMLLoader,
    }

    content = req["base64Content"]
    file_bytes = base64.b64decode(content)
    file = BytesIO(file_bytes)

    fd, path = tempfile.mkstemp()

    try:
        with os.fdopen(fd, "wb") as f:
            f.write(file.read())

        document_type = req["documentType"].upper()
        splitting_strategy = req["splittingStrategy"].upper()
        if document_type in loader_mapping:
            if (document_type == "MARKUP" and splitting_strategy == "MARKUP") or (
                document_type == "HTML" and splitting_strategy == "HTML"
            ):
                # return raw data for md and html splitters
                return file_bytes.decode()
            else:
                loader_class = loader_mapping[document_type]
                loader = loader_class(path)
        else:
            raise ValueError("File type not supported")

        documents = loader.load()

        # remove the source
        for doc in documents:
            doc.metadata.pop("source")

        return documents
    finally:
        os.remove(path)


def num_tokens_from_string(string: str, encoding_name="cl100k_base") -> int:
    if not string:
        return 0
    # Returns the number of tokens in a text string
    encoding = tiktoken.get_encoding(encoding_name)
    num_tokens = len(encoding.encode(string))
    return num_tokens


def split_document_by_splitter_type(
    documents,
    document_type,
    splitter="RECURSIVE",
    secondary_splitter="RECURSIVE",
    headers_to_split_on=None,
    chunk_size=4000,
    chunk_overlap=200,
    length_function=len,
):

    MARKUP_HEADERS = [
        ("#", "Header 1"),
        ("##", "Header 2"),
        ("###", "Header 3"),
        ("####", "Header 4"),
    ]

    HTML_HEADERS = [
        ("h1", "Header 1"),
        ("h2", "Header 2"),
        ("h3", "Header 3"),
        ("h4", "Header 4"),
        ("h5", "Header 5"),
        ("h6", "Header 6"),
    ]

    splitter_mapping = {
        "RECURSIVE": RecursiveCharacterTextSplitter,
        "TOKEN": TokenTextSplitter,
        "MARKUP": MarkdownHeaderTextSplitter,
        "HTML": HTMLHeaderTextSplitter,
    }

    if splitter == "RECURSIVE" or splitter == "TOKEN":
        chosen_splitter = splitter_mapping.get(splitter)(
            chunk_size=chunk_size,
            chunk_overlap=chunk_overlap,
            length_function=length_function,
        )
        new_list = []
        for chunk in chosen_splitter.split_documents(documents):
            text = chunk.page_content.replace("\n", " ")
            item = {}
            item["content"] = text
            item["tokenLength"] = num_tokens_from_string(text)
            item["metadata"] = chunk.metadata
            new_list.append(item)
        if new_list == []:
            raise ValueError("There is no content in this document.")
        return new_list

    elif splitter == "MARKUP" or splitter == "HTML":
        if headers_to_split_on is None:
            if splitter == "HTML" and document_type == "HTML":
                headers_to_split_on = HTML_HEADERS
            elif splitter == "MARKUP" and document_type == "MARKUP":
                headers_to_split_on = MARKUP_HEADERS
            else:
                raise ValueError("The MARKUP and HTML splitter can only be used with MARKUP and HTML documents respectively.")

        chosen_splitter = splitter_mapping.get(splitter)(
            headers_to_split_on=headers_to_split_on
        )

        second_splitter = splitter_mapping.get(secondary_splitter)(
            chunk_size=chunk_size,
            chunk_overlap=chunk_overlap,
            length_function=length_function,
        )

        new_list = []
        header_chunks = chosen_splitter.split_text(documents)
        for c in header_chunks:
            content = c.page_content.replace("\n", " ")
            for c2 in second_splitter.split_text(content.strip()):
                text = c2.replace("\n", " ")
                item = {}
                item["content"] = text
                item["tokenLength"] = num_tokens_from_string(text)
                item["metadata"] = c.metadata
                new_list.append(item)
        if new_list == []:
            raise ValueError("There is no content in this document.")
        return new_list


def validate_json_data(json_data):
    json_data["chunkSize"] = json_data.get("chunkSize", 4000)
    if json_data["chunkSize"] <= 1:
        raise ValueError("Chunk size should be greater than 1.")
    json_data["chunkOverlap"] = json_data.get("chunkOverlap", 200)
    if json_data["chunkOverlap"] < 0:
        raise ValueError("Chunk overlap should be 0 or greater.")

    valid_primary_splitters = {"RECURSIVE", "TOKEN", "MARKUP", "HTML"}
    json_data["splittingStrategy"] = json_data.get("splittingStrategy", "RECURSIVE")
    if json_data["splittingStrategy"].upper() not in valid_primary_splitters:
        raise ValueError("Invalid primary splitter value.")

    valid_secondary_splitters = {"RECURSIVE", "TOKEN"}
    json_data["secondarySplittingStrategy"] = json_data.get("secondarySplittingStrategy", "RECURSIVE")
    if json_data["secondarySplittingStrategy"].upper() not in valid_secondary_splitters:
        raise ValueError("Invalid secondary splitter value.")


def split_document(json_data, document):
    splitter = json_data.get("splittingStrategy").upper()
    secondary_splitter = json_data.get(
        "secondarySplittingStrategy").upper()
    headers_to_split_on = json_data.get("headersToSplitOn", None)
    chunk_size = json_data.get("chunkSize")
    chunk_overlap = json_data.get("chunkOverlap")
    document_type = json_data["documentType"].upper()
    return split_document_by_splitter_type(
        document,
        document_type,
        splitter=splitter,
        secondary_splitter=secondary_splitter,
        headers_to_split_on=headers_to_split_on,
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
    )


def main(req):
    try:
        json_data = req
    except json.JSONDecodeError:
        raise ValueError("Invalid JSON data.")

    validate_json_data(json_data)
    document = load_file(json_data)
    chunks = split_document(json_data, document)
    return json.dumps(chunks)
