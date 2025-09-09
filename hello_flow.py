from prefect import flow, get_run_logger

@flow(name="hello_flow")
def hello_flow():
    logger = get_run_logger()
    logger.info("Flow has started!")
    print("Hello from Prefect flow!")
    logger.info("Flow completed!")

# Optional: run this script directly
if __name__ == "__main__":
    hello_flow()
